#!/usr/bin/env bash
# Convenience: pub get + run the Flutter app on Linux desktop.
set -euo pipefail

cd "$(dirname "$0")/../app"
flutter pub get
exec flutter run -d linux "$@"
