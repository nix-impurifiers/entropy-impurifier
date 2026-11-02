# SPDX-License-Identifier: MIT
{
  pkgs,
  tools,
  impurifier,
  coreSrc,
}:
{
  native-package = impurifier.buildPackage {
    name = "native-marker";
    version = "1";
    payload =
      pkgs.runCommand "native-entropy-payload" { }
        "mkdir -p $out/usr/share/entropy-vm; echo native > $out/usr/share/entropy-vm/marker";
  };
  native-vm = import ./vm.nix {
    inherit
      pkgs
      impurifier
      tools
      coreSrc
      ;
  };
  native-import =
    pkgs.runCommand "entropy-native-import" { nativeBuildInputs = [ tools.package ]; }
      ''
            export ETP_ROOT=$TMPDIR/root
            mkdir -p "$ETP_ROOT"
            status=0
        equo --help > $out || status=$?
        test "$status" = 0 -o "$status" = 1
        grep -i 'entropy' $out
      '';
}
