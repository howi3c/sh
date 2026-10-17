# Offline reinstall acceptance materials

**These are test materials, not distribution releases or bootable installers.**
The test-only trust anchor must never be added to production TRUST.

`release-key.gpg` contains only a public Ed25519 certificate. Its fingerprint
is recorded in `metadata.json`. The private signing key and SSH private key
are not committed. `login.pub` is only an example public login key.

The genuine OpenPGP cleartext Debian Release signatures and detached Ubuntu
checksum signatures were created offline with Sequoia `sq`, reference time
2026-10-16, using this disposable test key. Acceptance fixes the wall-clock
boundary to 2026-10-17; it does not replace the verifier or bypass expiry checks.
A separate expired-release scenario moves that clock forward.

The binary synthetic kernel/ISO are inert byte sequences. The synthetic initrd
is genuine gzip/newc containing an inert ELF-prefixed wget file, an inert
executable debootstrap shell script, and the public fixture archive keyring, so
production archive parsing and overlay generation can run. None is executed. All three
artifacts exceed the installer's minimum size. Their genuine signed SHA256
checksums authenticate their exact contents; corruption tests alter responses
AFTER signing. Fixture extraction replaces only the xorriso OS boundary.

Runtime dependencies: Python 3, Bash, awk, gpgv, ssh-keygen and OpenSSL on PATH.
No network, root privileges, package installation or real reboot is required.
Missing dependencies produce a clear failure, not a silent successful skip.

Regeneration outline (use a fresh private temporary directory):

1. `sq --time 20261016T000000Z key generate --own-key --name 'Offline Reinstall Fixture NOT A DISTRIBUTION KEY' --without-password --expiration never --cannot-encrypt --cannot-authenticate --output signing.pgp --rev-cert revoke.pgp`
2. Export PUBLIC material only: `sq keyring filter --experimental --to-cert signing.pgp | sq packet dearmor > release-key.gpg`.
3. Recompute SHA256 listings and Debian signed Release size/digest records.
4. `sq --time 20261016T010000Z sign --signer-file signing.pgp --cleartext --output debian-VERSION-InRelease debian-VERSION-Release`.
5. `sq --time 20261016T010000Z sign --signer-file signing.pgp --binary --signature-file ubuntu-VERSION-SHA256SUMS.gpg ubuntu-VERSION-SHA256SUMS`.
6. Update metadata fingerprint. Verify with real gpgv. Delete private keys.

All test writes, including GRUB configs, environment, entry, lock, backups and
credential-bearing overlays, stay under the test's private temporary directory.
The adapter rejects unknown commands and never executes generated GRUB shell.
