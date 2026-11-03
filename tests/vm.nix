# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  tools,
  coreSrc,
  bundled ? false,
}:
let
  stage3 = import ./gentoo.nix { inherit pkgs; };
  stageTar = pkgs.runCommand "gentoo-stage3-uncompressed.tar" {
    nativeBuildInputs = [ pkgs.xz ];
  } ''xz -dc ${stage3} > "$out"'';
  tool =
    version:
    pkgs.runCommand "entropy-tool-${version}"
      {
        pname = "entropy-tool";
        inherit version;
        meta.license = pkgs.lib.licenses.mit;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/entropy-tool
        chmod 755 $out/bin/entropy-tool
      '';
  app =
    offline: version:
    impurifier.makePackageArtifact {
      pkg = tool version;
      inherit offline;
      users.entropy-worker = { };
      directories."/var/lib/entropy-worker" = {
        owner = "entropy-worker:entropy-worker";
        mode = "0750";
      };
      configFiles."/etc/entropy-app.conf" = pkgs.writeText "entropy-app.conf" "version=${version}\n";
      lifecycle = {
        onInstall = "echo initialized > /var/lib/entropy-worker/initialized";
        onUpgrade = "test ! -e /var/lib/entropy-worker/fail; echo ${version} > /var/lib/entropy-worker/migrated";
      };
    };
  runtime = impurifier.makeRuntimePackage {
    nixDependency = "app-impurifiers/nix-provider";
    pythonDependency = "app-impurifiers/python-provider";
  };
  provider =
    name:
    impurifier.buildPackage {
      inherit name;
      version = "1";
      payload =
        pkgs.runCommand "${name}-fixture" { }
          "mkdir -p $out/usr/share/impurifier-vm; echo preinstalled > $out/usr/share/impurifier-vm/${name}";
    };
  fixture = import (coreSrc + "/tests/hardware-fixture.nix") { inherit pkgs; };
  driver =
    version:
    impurifier.buildPackage {
      name = "host-driver";
      inherit version;
      payload = fixture.driver version;
    };
  hardware = impurifier.makeOfflinePackage {
    pkg = fixture.tool;
    inherit (fixture) hardware;
    hostDependencies = [ "app-impurifiers/host-driver" ];
  };
  oldRuntime = impurifier.makeRuntimePackage {
    version = "0.1";
    nixDependency = "app-impurifiers/nix-provider";
    pythonDependency = "app-impurifiers/python-provider";
  };
  nativeProof = pkgs.pkgsStatic.stdenv.mkDerivation {
    name = "native-static-proof";
    dontUnpack = true;
    buildPhase = ''
      cat > proof.c <<'C'
      #include <stdio.h>
      int main(void) { puts("Hello from native payload"); return 0; }
      C
      $CC proof.c -o proof
    '';
    installPhase = "mkdir -p $out/bin; cp proof $out/bin/";
  };
  nativePackage =
    version:
    impurifier.makeNativePackage {
      name = "native-marker";
      inherit version;
      payload = pkgs.runCommand "native-entropy-payload-${version}" { } ''
        mkdir -p $out/usr/share/entropy-vm $out/usr/libexec/native-entropy
        echo native > $out/usr/share/entropy-vm/marker
        echo ${version} > $out/usr/share/entropy-vm/version
        cp ${nativeProof}/bin/proof $out/usr/libexec/native-entropy/proof
      '';
    };
  package = nativePackage "1";

in
pkgs.testers.runNixOSTest {
  name = "entropy-native-contract";
  requiredFeatures = {
    kvm = false;
    devnet = false;
  };
  nodes.machine = { lib, ... }: {
    virtualisation.diskSize = 8192;
    virtualisation.memorySize = 2048;
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    nix.settings.substituters = lib.mkForce [ ];
    environment.systemPackages = [
      tools.package
      pkgs.nix
      pkgs.gnutar
      pkgs.xz
    ];
  };
  testScript = ''
    import shlex
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /srv/gentoo; tar xf ${stageTar} -C /srv/gentoo; mkdir -p /srv/gentoo/nix /srv/gentoo/proc /srv/gentoo/dev /srv/gentoo/sys")
    machine.succeed("mount --rbind /nix /srv/gentoo/nix; mount -t proc proc /srv/gentoo/proc; mount --rbind /dev /srv/gentoo/dev; mount --rbind /sys /srv/gentoo/sys")
    machine.succeed("mkdir -p /srv/gentoo/impurifiers/profiles/test /srv/gentoo/impurifiers/metadata; echo 8 > /srv/gentoo/impurifiers/profiles/test/eapi; printf 'ARCH=amd64\\nCHOST=x86_64-pc-linux-gnu\\nACCEPT_KEYWORDS=amd64\\nCONFIG_PROTECT=/etc\\n' > /srv/gentoo/impurifiers/profiles/test/make.defaults; echo app-impurifiers > /srv/gentoo/impurifiers/profiles/categories")
    machine.succeed("rm -f /srv/gentoo/etc/portage/make.profile; ln -s /impurifiers/profiles/test /srv/gentoo/etc/portage/make.profile; printf '[DEFAULT]\\nmain-repo=impurifiers\\n[impurifiers]\\nlocation=/impurifiers\\nauto-sync=no\\n' > /srv/gentoo/etc/portage/repos.conf; printf 'FEATURES=\"-sandbox -usersandbox -userpriv -network-sandbox -pid-sandbox -ipc-sandbox -mount-sandbox -news\"\\n' > /srv/gentoo/etc/portage/make.conf")
    machine.succeed("mkdir -p /srv/gentoo/etc/entropy; cp -r ${tools.source}/conf/. /srv/gentoo/etc/entropy/; chmod -R u+w /srv/gentoo/etc/entropy; rm -rf /srv/gentoo/etc/entropy/repositories.conf.d; printf 'product=impurifiers\\nbranch=impurifiers\\n' > /srv/gentoo/etc/entropy/repositories.conf")
    machine.succeed("chroot /srv/gentoo /usr/sbin/groupadd -r entropy")
    module = machine.succeed("find /srv/gentoo/usr -path '*/portage/__init__.py' | head -1").strip()
    assert module
    portage_path = module.removeprefix("/srv/gentoo").rsplit("/portage/__init__.py", 1)[0]
    root = "chroot /srv/gentoo /usr/bin/env PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C PYTHONPATH=" + shlex.quote(portage_path) + " "
    machine.succeed(root + "${tools.package}/bin/equo --version")
    pythonpath = "${tools.package}/lib/python:" + portage_path
    machine.succeed(root + "PYTHONPATH=" + shlex.quote(pythonpath) + " ${tools.python}/bin/python3 ${./initialize.py}")
    machine.succeed(root + "PYTHONPATH=" + shlex.quote(pythonpath) + " ${tools.python}/bin/python3 ${./vdb-lock.py}")
    machine.succeed("mkdir -p /srv/gentoo/packages; cp ${package}/app-impurifiers/*.tbz2 /srv/gentoo/packages/; chmod u+w /srv/gentoo/packages/*")
    machine.succeed("timeout 60 " + root + "${tools.package}/bin/equo install /packages/app-impurifiers:native-marker-1~0.tbz2 < /dev/null > /srv/gentoo/tmp/install.log 2>&1 || { cat /srv/gentoo/tmp/install.log; exit 1; }")
    machine.succeed("grep native /srv/gentoo/usr/share/entropy-vm/marker; test -d /srv/gentoo/var/db/pkg/app-impurifiers/native-marker-1")
    machine.fail(root + "/bin/sh -c 'command -v nix-store'")
    machine.succeed("mkdir -p /srv/native; cp /srv/gentoo/usr/libexec/native-entropy/proof /srv/native/proof; chroot /srv/native /proof | grep Hello; test ! -e /srv/native/nix")
    machine.succeed("cp ${nativePackage "2"}/app-impurifiers/*.tbz2 /srv/gentoo/packages/; chmod u+w /srv/gentoo/packages/*")
    machine.succeed("timeout 60 " + root + "${tools.package}/bin/equo install /packages/app-impurifiers:native-marker-2~0.tbz2 < /dev/null > /srv/gentoo/tmp/native-upgrade.log 2>&1 || { cat /srv/gentoo/tmp/native-upgrade.log; exit 1; }")
    machine.succeed("grep '^2$' /srv/gentoo/usr/share/entropy-vm/version; test -d /srv/gentoo/var/db/pkg/app-impurifiers/native-marker-2")
    machine.succeed("timeout 60 " + root + "${tools.package}/bin/equo remove app-impurifiers/native-marker < /dev/null > /srv/gentoo/tmp/remove.log 2>&1 || { cat /srv/gentoo/tmp/remove.log; exit 1; }")
    machine.succeed("test ! -e /srv/gentoo/usr/share/entropy-vm/marker && test ! -e /srv/gentoo/usr/libexec/native-entropy/proof")
    machine.succeed("mkdir -p /srv/gentoo/opt/nix /opt/nix /srv/gentoo/var/lib/entropy-impurifier /var/lib/entropy-impurifier; mount --bind /opt/nix /srv/gentoo/opt/nix; mount --bind /var/lib/entropy-impurifier /srv/gentoo/var/lib/entropy-impurifier; ln -s ${
      if bundled then
        pkgs.writeShellScript "incompatible-nix-store" "echo incompatible; exit 1"
      else
        "${pkgs.nix}/bin/nix-store"
    } /srv/gentoo/usr/bin/nix-store; ln -s ${tools.package}/bin/equo /srv/gentoo/usr/bin/equo")
    def native_install(artifact, pattern="*.tbz2", expect_success=True, flags="", adapter=False):
        machine.succeed("rm -rf /srv/gentoo/packages/*; cp " + artifact + "/app-impurifiers/" + pattern + " /srv/gentoo/packages/; chmod u+w /srv/gentoo/packages/*")
        archive = machine.succeed("ls /srv/gentoo/packages/*.tbz2").strip().removeprefix("/srv/gentoo")
        program = "/usr/sbin/entropy-impurifier" if adapter else "${tools.package}/bin/equo"
        command = "timeout 60 " + root + program + " install " + flags + " " + shlex.quote(archive) + " < /dev/null > /srv/gentoo/tmp/transaction.log 2>&1"
        if expect_success:
            machine.succeed(command + " || { cat /srv/gentoo/tmp/transaction.log; exit 1; }")
        else:
            machine.fail(command)
    native_install("${provider "nix-provider"}")
    native_install("${provider "python-provider"}")
    native_install("${runtime}")
    machine.succeed("test ! -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
    native_install("${app false "1"}", expect_success=False)
    native_install("${app true "1"}", adapter=True)
    machine.succeed(root + "/opt/nix/profile/bin/entropy-tool | grep '^1$'; test $(stat -c %a /srv/gentoo/var/lib/entropy-worker) = 750; grep initialized /srv/gentoo/var/lib/entropy-worker/initialized")
    machine.succeed("echo customized > /srv/gentoo/etc/entropy-app.conf; touch /srv/gentoo/var/lib/entropy-worker/fail")
    native_install("${app true "2"}", expect_success=False)
    machine.succeed("rm /srv/gentoo/var/lib/entropy-worker/fail")
    machine.succeed(root + "/usr/sbin/entropy-impurifier reconcile")
    machine.succeed(root + "/opt/nix/profile/bin/entropy-tool | grep '^2$'")
    machine.succeed("grep 2 /srv/gentoo/var/lib/entropy-worker/migrated; grep customized /srv/gentoo/etc/entropy-app.conf")
    native_install("${oldRuntime}", expect_success=False, flags="--nodeps")
    machine.succeed("grep '^0.1$' /srv/gentoo/usr/share/entropy-impurifier/runtime-version")
    machine.succeed(root + "/opt/nix/profile/bin/entropy-tool | grep '^2$'")
    native_install("${runtime}")
    native_install("${driver "1"}")
    native_install("${hardware}")
    machine.succeed(root + "/opt/nix/profile/bin/hardware-tool | grep '^1$'")
    native_install("${driver "2"}")
    machine.succeed(root + "/usr/sbin/entropy-impurifier reconcile; /opt/nix/profile/bin/hardware-tool | grep '^2$'")
    machine.succeed("nix-collect-garbage")
    machine.succeed(root + "/opt/nix/profile/bin/entropy-tool | grep '^2$'")
    machine.fail(root + "ETP_ROOT=/foreign /usr/sbin/entropy-impurifier reconcile")
    machine.succeed(root + "/usr/sbin/entropy-impurifier remove app-impurifiers/hardware-tool-offline app-impurifiers/host-driver > /srv/gentoo/tmp/remove-hardware.log 2>&1 || { cat /srv/gentoo/tmp/remove-hardware.log; exit 1; }")
    machine.succeed(root + "/usr/sbin/entropy-impurifier remove app-impurifiers/entropy-tool-offline > /srv/gentoo/tmp/remove-app.log 2>&1 || { cat /srv/gentoo/tmp/remove-app.log; exit 1; }")
    machine.succeed("test ! -e /opt/nix/profile/bin/entropy-tool; test -f /srv/gentoo/var/lib/entropy-worker/initialized; grep customized /srv/gentoo/etc/entropy-app.conf")

  '';
}
