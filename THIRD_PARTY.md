# Third-party software

Original compiler, adapter, compatibility patches, and tests are MIT licensed.

The native Entropy client is Sabayon/entropy revision
`aeff7dd466be6e0218709d32b03f3aa35cb2b4d8`, licensed GPL-2. Its original
copyright headers remain in the installed modules, and its COPYING is installed
under `share/licenses/entropy/COPYING` in the native tool output.

The tool relocates Entropy's installation data path and adapts Python thread and
text-file APIs for Python 3.12. Its Portage bridge shares a native VDB lock across
nested Entropy operations, uses modern Portage's own database lock when available,
and adapts the counter-method arguments to the installed Portage API. These
patches do not fabricate package counters or bypass cross-process locking.

The VM fixture uses an upstream Gentoo stage3 and its real Portage implementation.
Their licenses and notices remain in the stage3 archive. They are test fixtures,
not components bundled inside generated application packages.
