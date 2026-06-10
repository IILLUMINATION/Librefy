#!/usr/bin/env bash
# Build the Librefy native torrent bridge (liblibrefy_torrent.so) for the
# current Linux host. The output is staged into app/linux/libs/ so the
# Flutter Linux build picks it up automatically through CMake.
#
# For Android cross-builds use scripts/build-native-android.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/native/librefy-torrent"
OUT="${ROOT}/app/linux/libs"

mkdir -p "${OUT}"
echo "→ building liblibrefy_torrent.so (linux/amd64)…"
cd "${SRC}"
CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
  go build -buildmode=c-shared -ldflags="-s -w -checklinkname=0" \
  -o "${OUT}/liblibrefy_torrent.so" .

SIZE=$(stat -c%s "${OUT}/liblibrefy_torrent.so" 2>/dev/null || stat -f%z "${OUT}/liblibrefy_torrent.so")
echo "✓ ${OUT}/liblibrefy_torrent.so ($(numfmt --to=iec "${SIZE}" 2>/dev/null || echo "${SIZE} bytes"))"
