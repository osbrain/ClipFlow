#!/bin/bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TOOLS_DIR="$ROOT_DIR/.build-tools"
BOTTLE_OS="${CLIPFLOW_BOTTLE_OS:-sonoma}"

if [[ -f "$TOOLS_DIR/sqlcipher/static-lib/libsqlcipher.a" && \
      -f "$TOOLS_DIR/openssl/lib/libcrypto.a" && \
      "$(otool -l "$TOOLS_DIR/sqlcipher/static-lib/libsqlcipher.a" | awk '/minos/{print $2; exit}')" == "14.0" && \
      "$(otool -l "$TOOLS_DIR/openssl/lib/libcrypto.a" | awk '/minos/{print $2; exit}')" == "14.0" ]]; then
    echo "ClipFlow development dependencies are ready."
    exit 0
fi

command -v brew >/dev/null 2>&1 || {
    echo "Homebrew is required to bootstrap local SQLCipher development libraries." >&2
    exit 1
}

HOMEBREW_NO_AUTO_UPDATE=1 brew fetch --os="$BOTTLE_OS" --arch=arm sqlcipher openssl@4

DOWNLOADS_DIR="$(brew --cache)/downloads"
SQLCIPHER_BOTTLE=$(find "$DOWNLOADS_DIR" -type f -name "*--sqlcipher--*.arm64_${BOTTLE_OS}.bottle.tar.gz" -print -quit)
OPENSSL_BOTTLE=$(find "$DOWNLOADS_DIR" -type f -name "*--openssl@4--*.arm64_${BOTTLE_OS}.bottle*.tar.gz" -print -quit)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

mkdir -p "$TEMP_DIR/sqlcipher" "$TEMP_DIR/openssl"
tar -xzf "$SQLCIPHER_BOTTLE" -C "$TEMP_DIR/sqlcipher"
tar -xzf "$OPENSSL_BOTTLE" -C "$TEMP_DIR/openssl"

SQLCIPHER_ARCHIVE=$(find "$TEMP_DIR/sqlcipher" -type f -name libsqlcipher.a -print -quit)
OPENSSL_ARCHIVE=$(find "$TEMP_DIR/openssl" -type f -name libcrypto.a -print -quit)

[[ -n "$SQLCIPHER_BOTTLE" && -n "$OPENSSL_BOTTLE" && -n "$SQLCIPHER_ARCHIVE" && -n "$OPENSSL_ARCHIVE" ]] || {
    echo "Downloaded bottles do not contain the required static libraries." >&2
    exit 1
}

mkdir -p "$TOOLS_DIR/sqlcipher/static-lib" "$TOOLS_DIR/openssl/lib"
rm -f "$TOOLS_DIR/sqlcipher/static-lib/libsqlcipher.a" "$TOOLS_DIR/openssl/lib/libcrypto.a"
cp "$SQLCIPHER_ARCHIVE" "$TOOLS_DIR/sqlcipher/static-lib/libsqlcipher.a"
cp "$OPENSSL_ARCHIVE" "$TOOLS_DIR/openssl/lib/libcrypto.a"

echo "ClipFlow development dependencies are ready."
