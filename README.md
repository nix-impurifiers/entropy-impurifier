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

## Native payloads and bundled clients

`makeNativePackage { name; version; payload; dependencies?; ... }` emits a
native Entropy package from a producer-prepared filesystem tree, with activation
triggers disabled and no implicit Nix requirement. The producer supplies a
working target layout; this does not relocate binaries. The VM checks native
installation, upgrade and removal with actual Portage VDB integration before
installing the engine, then executes the installed static payload in an isolated
root without `/nix`. The native manager fixture uses Gentoo and SDK host tools;
this does not claim a full Sabayon boot without Nix.

`makeRuntimePackage` optionally accepts `bundledNixStore` and
`bundledNixNotices` for a static ELF client with upstream notices. Bundling omits
the default Nix dependency; Python remains required. Compatible external clients
take precedence, explicit `IMPURIFIER_NIX_STORE` disables fallback, and failed
mutations are never retried through another client. A bundled variant repeats
the original lifecycle suite with an incompatible external candidate. The Nix
provider/installer remains deferred.
