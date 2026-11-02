# entropy-impurifier

Build native Entropy `.tbz2` packages projecting Nix applications into a shared
`/opt/nix/profile`. The compiler emits native tar payloads, Portage XPAK metadata,
and Entropy SQLite metadata using the upstream format APIs.

```nix
let
  impurifier = inputs.entropy-impurifier.lib.entropy-impurifier { inherit pkgs; };
in impurifier.makePackage { pkg = pkgs.hello; }
```

`makePackage` returns `net` and `offline` artifacts. `makeNetPackage` and
`makeOfflinePackage` select one explicitly. Outputs contain canonical package
filenames under `app-impurifiers/`; copy their contents outside the Nix store
before using native `equo install`, which opens local packages for writing.
The installed `entropy-impurifier install ARCHIVE...` adapter makes writable
copies automatically. It also supports `remove CATEGORY/PACKAGE...` and
`reconcile` for reporting and retrying activation failures.

Install `makeRuntimePackage { ... }` first. It depends on native Nix and Python
packages; `nixDependency` and `pythonDependency` let hosts express their own
provider identities. These dependencies do not install Nix by themselves. A Nix
provider package and installer remain deferred work.

Applications support the shared engine's accounts, directories, configuration
files, lifecycle hooks, offline closure import, and explicit host-library
bridging. `hostDependencies` adds native Entropy dependency atoms. Init-system
service integration needs separate host verification and is rejected for now.
A native package transaction can finish file installation while an activation
hook fails; inspect the native transaction output, correct the cause, then run
`entropy-impurifier reconcile`.

This backend targets Entropy's package contract and its real Portage database
integration. It does not claim that a current Sabayon distribution exists or
that the tests cover Sabayon boot and desktop behavior.

Run `nix flake check -L` for native QEMU tests. Original code is MIT licensed;
see [THIRD_PARTY.md](THIRD_PARTY.md) for native runtime notices and compatibility
patches.
