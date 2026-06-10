#!/usr/bin/env bash
# Convenience: pub get + run the Flutter app on Linux desktop.
# Ensures libmpv (the only native dependency) is present first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# media_kit needs libmpv to be discoverable at runtime. If it isn't,
# offer to install it via the bundled setup script (one-shot, idempotent).
if ! ldconfig -p 2>/dev/null | grep -q 'libmpv\.so'; then
  echo "libmpv not found — running scripts/setup.sh to install it…"
  "${ROOT}/scripts/setup.sh"
fi

cd "${ROOT}/app"
flutter pub get
exec flutter run -d linux "$@"
