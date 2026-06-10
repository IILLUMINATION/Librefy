#!/usr/bin/env bash
# Rasterises the brand SVGs into every density bucket Android needs.
#
# Inputs:
#   app/assets/branding/icon.svg            — legacy / web / play-store icon
#   app/assets/branding/icon_foreground.svg — adaptive-icon foreground layer
#
# Outputs:
#   app/android/app/src/main/res/mipmap-<density>/ic_launcher.png
#                                              /ic_launcher_foreground.png
#   app/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
#   app/android/app/src/main/res/values/ic_launcher_background.xml
#   app/assets/branding/icon-512.png            — Play Store listing
#   app/assets/branding/icon-1024.png           — masters / app store icon
#   app/web/icons/ + favicon (if web build is present)
#
# Requires: rsvg-convert (librsvg2-bin) OR magick (ImageMagick 7+).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/app/assets/branding"
RES="${ROOT}/app/android/app/src/main/res"

ICON_SVG="${SRC}/icon.svg"
FG_SVG="${SRC}/icon_foreground.svg"

if [[ ! -f "${ICON_SVG}" || ! -f "${FG_SVG}" ]]; then
  echo "✗ missing master SVGs in ${SRC}" >&2
  exit 1
fi

# Pick a rasteriser.
if command -v rsvg-convert >/dev/null 2>&1; then
  rasterise() { rsvg-convert -w "$1" -h "$1" "$2" -o "$3"; }
elif command -v magick >/dev/null 2>&1; then
  rasterise() { magick -background none -density 300 "$2" -resize "${1}x${1}" "$3"; }
else
  echo "✗ need rsvg-convert or ImageMagick (magick)" >&2
  exit 1
fi

# Android launcher icon sizes per density bucket.
declare -A LEGACY=(
  [mdpi]=48
  [hdpi]=72
  [xhdpi]=96
  [xxhdpi]=144
  [xxxhdpi]=192
)

# Adaptive foreground is always 108dp, rasterised to the same buckets.
declare -A ADAPTIVE=(
  [mdpi]=108
  [hdpi]=162
  [xhdpi]=216
  [xxhdpi]=324
  [xxxhdpi]=432
)

echo "→ Android legacy ic_launcher.png"
for density in "${!LEGACY[@]}"; do
  out="${RES}/mipmap-${density}"
  mkdir -p "${out}"
  rasterise "${LEGACY[$density]}" "${ICON_SVG}" "${out}/ic_launcher.png"
  echo "  ✓ ${density}: ${LEGACY[$density]}px"
done

echo "→ Android adaptive ic_launcher_foreground.png"
for density in "${!ADAPTIVE[@]}"; do
  out="${RES}/mipmap-${density}"
  mkdir -p "${out}"
  rasterise "${ADAPTIVE[$density]}" "${FG_SVG}" "${out}/ic_launcher_foreground.png"
  echo "  ✓ ${density}: ${ADAPTIVE[$density]}px"
done

# Adaptive icon XML (Android 8.0+) and background colour.
ADAPTIVE_DIR="${RES}/mipmap-anydpi-v26"
mkdir -p "${ADAPTIVE_DIR}"
cat > "${ADAPTIVE_DIR}/ic_launcher.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
EOF
cat > "${ADAPTIVE_DIR}/ic_launcher_round.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
EOF

# Background colour — matches the dark end of the icon gradient so
# launchers that don't render the SVG see a flat brand-colour.
VALUES_DIR="${RES}/values"
mkdir -p "${VALUES_DIR}"
cat > "${VALUES_DIR}/ic_launcher_background.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#4F3A87</color>
</resources>
EOF

# Round launcher (older Pixel-style mask) — re-use the legacy raster.
for density in "${!LEGACY[@]}"; do
  cp "${RES}/mipmap-${density}/ic_launcher.png" \
     "${RES}/mipmap-${density}/ic_launcher_round.png"
done

# Master PNGs for store listing / desktop builds.
rasterise 512  "${ICON_SVG}" "${SRC}/icon-512.png"
rasterise 1024 "${ICON_SVG}" "${SRC}/icon-1024.png"
echo "  ✓ ${SRC}/icon-512.png, ${SRC}/icon-1024.png"

# Web icons (best-effort: only if the web platform folder exists).
WEB="${ROOT}/app/web"
if [[ -d "${WEB}" ]]; then
  mkdir -p "${WEB}/icons"
  rasterise 192 "${ICON_SVG}" "${WEB}/icons/Icon-192.png"
  rasterise 512 "${ICON_SVG}" "${WEB}/icons/Icon-512.png"
  rasterise 192 "${ICON_SVG}" "${WEB}/icons/Icon-maskable-192.png"
  rasterise 512 "${ICON_SVG}" "${WEB}/icons/Icon-maskable-512.png"
  rasterise 32  "${ICON_SVG}" "${WEB}/favicon.png"
  echo "  ✓ web/icons + favicon"
fi

echo "✓ icons built"
