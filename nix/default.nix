# SPDX-License-Identifier: MIT
{
  pkgs,
  coreSrc,
  sourceInfo ? { },
}:
let
  inherit (pkgs) lib;
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    namespace = "entropy-impurifier";
    sourceInfo.lastModified = lib.max (
      if builtins.isAttrs coreSrc then coreSrc.lastModified or 0 else 0
    ) (if builtins.isAttrs sourceInfo then sourceInfo.lastModified or 0 else 0);
  };
  activationTrigger = builtins.readFile ../src/package-trigger.py;
  tools = import ./tools.nix { inherit pkgs; };
  buildPackage =
    {
      name,
      version,
      payload,
      category ? "app-impurifiers",
      dependencies ? [ ],
      conflicts ? [ ],
      trigger ? "",
      license ? "MIT",
      description ? "Nix projected application",
      revision ? 0,
    }:
    assert lib.assertMsg (lib.all (v: builtins.match "[a-z0-9][a-z0-9+._-]*" v != null) [
      name
      version
      category
    ]) "invalid Entropy package identity";
    pkgs.runCommand "${name}-${version}-entropy"
      {
        nativeBuildInputs = [ tools.python ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
        passthru = { inherit name version; };
      }
      ''
        export ETP_ROOT=$TMPDIR/entropy-root
        mkdir -p "$ETP_ROOT" "$out"
        export PYTHONPATH=${tools.package}/lib/python
        python3 ${../src/build-package.py} ${payload} "$out" ${
          pkgs.writeText "entropy-metadata.json" (
            builtins.toJSON {
              inherit
                name
                version
                category
                dependencies
                conflicts
                trigger
                license
                description
                revision
                ;
            }
          )
        }
      '';
  makeRuntimePackage =
    {
      bundledNixStore ? null,
      bundledNixNotices ? [ ],
      nixDependency ? (if bundledNixStore == null then "sys-apps/nix" else null),
      pythonDependency ? "dev-lang/python",
      version ? core.runtimeVersion,
    }:
    buildPackage {
      name = "entropy-impurifier";
      inherit version;
      dependencies = lib.optional (nixDependency != null) nixDependency ++ [ pythonDependency ];
      trigger = activationTrigger;
      payload = pkgs.runCommand "entropy-runtime" { } ''
        cp -r ${core.makeRuntimeTree { inherit bundledNixStore bundledNixNotices; }} $out
        chmod -R u+w $out
        install -Dm755 ${../src/activate.py} $out/usr/sbin/entropy-impurifier-activate
        install -Dm755 ${../src/adapter.py} $out/usr/sbin/entropy-impurifier
        mkdir -p $out/usr/share/entropy-impurifier
        echo '${version}' > $out/usr/share/entropy-impurifier/runtime-version
      '';
    };
  makePackageArtifact =
    args@{
      pkg,
      hostDependencies ? [ ],
      ...
    }:
    assert lib.assertMsg (
      (args.systemd or null) == null && (args.openrc or null) == null && (args.runit or null) == null
    ) "Entropy service integration needs a separately verified host init policy";
    let
      application = core.makePayload (
        (builtins.removeAttrs args [ "hostDependencies" ])
        // {
          hostBackend = "openrc";
        }
      );
      other = "${application.name}-${if application.offline then "net" else "offline"}";
    in
    buildPackage {
      name = application.packageName;
      inherit (application) version description;
      dependencies = [
        ">=app-impurifiers/entropy-impurifier-${core.runtimeVersion}"
      ]
      ++ hostDependencies;
      conflicts = [ "app-impurifiers/${other}" ];
      trigger = activationTrigger;
      license = lib.concatMapStringsSep " " (v: v.spdxId or "LicenseRef-Unknown") (
        lib.toList (pkg.meta.license or [ ])
      );
      payload = pkgs.runCommand "entropy-application" { } ''
        cp -r ${application} $out
        chmod -R u+w $out
        mkdir -p $out/usr/share/entropy-impurifier/requirements
        echo '${core.runtimeVersion}' > $out/usr/share/entropy-impurifier/requirements/${application.packageName}
      '';
    };
in
{
  inherit
    buildPackage
    tools
    makeRuntimePackage
    makePackageArtifact
    ;
  makeNativePackage = args: buildPackage (args // { trigger = ""; });
  runtimePackage = makeRuntimePackage { };
  makeNetPackage = args: makePackageArtifact (args // { offline = false; });
  makeOfflinePackage = args: makePackageArtifact (args // { offline = true; });
  makePackage = args: {
    net = makePackageArtifact (args // { offline = false; });
    offline = makePackageArtifact (args // { offline = true; });
  };
  inherit (core) unit;
}
