#!/usr/bin/env bash
# Cross-build the Librefy native torrent bridge for Android using the
# Go toolchain + Android NDK's clang. Output is staged into
# app/android/app/src/main/jniLibs/<abi>/ — Gradle picks it up.
#
# Required:
#   - Go ≥ 1.22
#   - ANDROID_NDK_HOME (or ANDROID_NDK_ROOT) pointing at an NDK r25+
#
# By default builds three ABIs: arm64-v8a, armeabi-v7a, x86_64.
# Set ABIS to override, e.g. ABIS="arm64-v8a" ./build-native-android.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/native/librefy-torrent"
OUT_BASE="${ROOT}/app/android/app/src/main/jniLibs"

# Locate NDK.
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [[ -z "${NDK}" ]]; then
  # Pick the highest version under ~/Android/Sdk/ndk.
  if [[ -d "${HOME}/Android/Sdk/ndk" ]]; then
    NDK="$(ls -d "${HOME}/Android/Sdk/ndk/"*/ | sort -V | tail -1)"
    NDK="${NDK%/}"
  fi
fi
if [[ -z "${NDK}" || ! -d "${NDK}" ]]; then
  echo "✗ Android NDK not found. Set ANDROID_NDK_HOME." >&2
  exit 1
fi
echo "→ NDK: ${NDK}"

HOST_TAG="linux-x86_64"
case "$(uname -s)" in
  Darwin) HOST_TAG="darwin-x86_64" ;;
esac

TOOLCHAIN="${NDK}/toolchains/llvm/prebuilt/${HOST_TAG}/bin"
if [[ ! -d "${TOOLCHAIN}" ]]; then
  echo "✗ Toolchain not at ${TOOLCHAIN}" >&2
  exit 1
fi

# Map ABI → (GOARCH, GOARM, clang-target-triple).
build_for_abi() {
  local abi="$1"
  local goarch goarm clang_triple
  # Android API level the resulting .so will be linked against.
  # 21 = Android 5.0 (Lollipop); this matches Flutter's default minSdk.
  local api="${ANDROID_API:-21}"
  case "${abi}" in
    arm64-v8a)
      goarch=arm64; goarm=""; clang_triple="aarch64-linux-android${api}" ;;
    armeabi-v7a)
      goarch=arm; goarm=7; clang_triple="armv7a-linux-androideabi${api}" ;;
    x86_64)
      goarch=amd64; goarm=""; clang_triple="x86_64-linux-android${api}" ;;
    *)
      echo "✗ unsupported ABI: ${abi}" >&2; return 1 ;;
  esac

  local cc="${TOOLCHAIN}/${clang_triple}-clang"
  local out_dir="${OUT_BASE}/${abi}"
  mkdir -p "${out_dir}"

  if [[ ! -x "${cc}" ]]; then
    echo "✗ clang binary missing: ${cc}" >&2
    return 1
  fi

  echo "→ building ${abi}…"
  (
    cd "${SRC}"
    export CGO_ENABLED=1
    export GOOS=android
    export GOARCH="${goarch}"
    if [[ -n "${goarm}" ]]; then export GOARM="${goarm}"; fi
    export CC="${cc}"
    export CXX="${cc}++"
    # `-checklinkname=0` is required because wlynxg/anet (transitive
    # dependency of anacrolix/torrent for Android-friendly IP enumeration)
    # uses //go:linkname against an unexported net package symbol that
    # newer Go versions block by default.
    go build -buildmode=c-shared \
      -ldflags="-s -w -checklinkname=0" \
      -o "${out_dir}/liblibrefy_torrent.so" .
  )
  echo "  ✓ ${out_dir}/liblibrefy_torrent.so"
}

ABIS="${ABIS:-arm64-v8a armeabi-v7a x86_64}"
for abi in ${ABIS}; do
  build_for_abi "${abi}"
done

echo "✓ Android native libs built"
