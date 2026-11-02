# Development

The public API lives in `nix/default.nix`. `src/build-package.py` uses native
Entropy format APIs; `nix/tools.nix` builds the pinned native client with the
compatibility changes listed in the root third-party notices. The runtime uses
the shared `impurifier` engine pinned by the flake.

`tests/vm.nix` runs the real client against a Gentoo stage3 inside QEMU. The native
Portage VDB and Entropy installed repository are both used. The VDB lock test
spawns a competing process rather than mocking a lock implementation.

Keep transport artifacts free of Nix references and verify offline activation
from a missing application store path. Failure tests must check the previous
application remains usable and retries preserve installation history. Do not
claim Sabayon boot/init support from the package transaction fixture.
