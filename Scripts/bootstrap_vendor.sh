#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/idevice"
mkdir -p "$DEST"
COMMIT="83c8fb324983728e8f44759cfd834dc637ee38b5"
BASE="https://raw.githubusercontent.com/ChrisMack32/Locus/$COMMIT/Vendor/idevice"

echo "Downloading pinned idevice FFI from Locus commit $COMMIT ..."
curl -fL --retry 3 "$BASE/idevice.h" -o "$DEST/idevice.h"
curl -fL --retry 3 "$BASE/libidevice_ffi.a" -o "$DEST/libidevice_ffi.a"
curl -fL --retry 3 "$BASE/module.modulemap" -o "$DEST/module.modulemap"

echo "Vendor files ready:"
ls -lh "$DEST/idevice.h" "$DEST/libidevice_ffi.a" "$DEST/module.modulemap"
