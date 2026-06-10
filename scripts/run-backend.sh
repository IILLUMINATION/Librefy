#!/usr/bin/env bash
# Run the Librefy backend with sensible defaults for local development.
# Use LIBREFY_ADDR / LIBREFY_DB / LIBREFY_SEED to override.
set -euo pipefail

cd "$(dirname "$0")/../backend"
exec go run ./cmd/librefyd "$@"
