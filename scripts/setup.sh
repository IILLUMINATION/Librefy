#!/usr/bin/env bash
# Librefy one-shot dev setup.
#
# Installs the only native dependency the Flutter app needs on Linux desktop:
# libmpv (used by media_kit for audio playback). On Android nothing here
# is required — the APK ships its own .so files.
#
# Usage:
#   ./scripts/setup.sh

set -euo pipefail

need_sudo() { command -v sudo >/dev/null && echo sudo || echo ""; }
SUDO=$(need_sudo)

have() { command -v "$1" >/dev/null 2>&1; }

# Quick check: is libmpv already discoverable?
if ldconfig -p 2>/dev/null | grep -q 'libmpv\.so'; then
  echo "✓ libmpv already installed."
  exit 0
fi

echo "→ libmpv not found, installing for your distro…"

if have apt-get; then
  $SUDO apt-get update
  $SUDO apt-get install -y libmpv2 libmpv-dev || $SUDO apt-get install -y libmpv1 libmpv-dev
elif have dnf; then
  $SUDO dnf install -y mpv-libs mpv-libs-devel
elif have pacman; then
  $SUDO pacman -S --needed --noconfirm mpv
elif have zypper; then
  $SUDO zypper install -y libmpv2 mpv-devel
elif have brew; then
  brew install mpv
else
  echo "✗ Unknown package manager. Install mpv/libmpv manually, then re-run." >&2
  exit 1
fi

echo "✓ libmpv installed."
