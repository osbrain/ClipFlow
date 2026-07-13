#!/bin/bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TOOLS_DIR="$ROOT_DIR/.build-tools"

if [[ -f "$TOOLS_DIR/sqlcipher/static-lib/libsqlcipher.a" && \
      -f "$TOOLS_DIR/openssl/lib/libcrypto.a" ]]; then
    echo "ClipFlow development dependencies are ready."
    exit 0
fi

command -v brew >/dev/null 2>&1 || {
    echo "Homebrew is required to bootstrap local SQLCipher development libraries." >&2
    exit 1
}

HOMEBREW_NO_AUTO_UPDATE=1 brew fetch sqlcipher openssl@4

SQLCIPHER_BOTTLE=$(HOMEBREW_NO_AUTO_UPDATE=1 brew --cache sqlcipher)
OPENSSL_BOTTLE=$(HOMEBREW_NO_AUTO_UPDATE=1 brew --cache openssl@4)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

mkdir -p "$TEMP_DIR/sqlcipher" "$TEMP_DIR/openssl"
tar -xzf "$SQLCIPHER_BOTTLE" -C "$TEMP_DIR/sqlcipher"
tar -xzf "$OPENSSL_BOTTLE" -C "$TEMP_DIR/openssl"

SQLCIPHER_ARCHIVE=$(find "$TEMP_DIR/sqlcipher" -type f -name libsqlcipher.a -print -quit)
OPENSSL_ARCHIVE=$(find "$TEMP_DIR/openssl" -type f -name libcrypto.a -print -quit)

[[ -n "$SQLCIPHER_ARCHIVE" && -n "$OPENSSL_ARCHIVE" ]] || {
    echo "Downloaded bottles do not contain the required static libraries." >&2
    exit 1
}

mkdir -p "$TOOLS_DIR/sqlcipher/static-lib" "$TOOLS_DIR/openssl/lib"
cp "$SQLCIPHER_ARCHIVE" "$TOOLS_DIR/sqlcipher/static-lib/libsqlcipher.a"
cp "$OPENSSL_ARCHIVE" "$TOOLS_DIR/openssl/lib/libcrypto.a"

echo "ClipFlow development dependencies are ready."

