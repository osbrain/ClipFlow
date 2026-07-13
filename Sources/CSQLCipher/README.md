# CSQLCipher Development Binding

This module exposes the SQLCipher 4.17.0 SQLite-compatible C API. The checked-in
header comes from the Homebrew `sqlcipher` 4.17.0 arm64 Tahoe bottle whose SHA-256
is `d9cfd925a0d2413971fcbee16934e9721b7c706f07bf8c8dacd76ba0214708fe`.

Local Command Line Tools builds use ignored static libraries under
`.build-tools/sqlcipher` and `.build-tools/openssl`. Release builds must compile
the SQLCipher 4.17.0 source archive with SHA-256
`79c0e164b9c059e7487bf8f29272f601cca5f3312cc267461f81e349962a5058` for both
architectures, then link the resulting universal static library.

