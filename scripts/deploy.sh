#!/usr/bin/env bash
# One-shot deploy: build a static linux/amd64 librefyd binary and ship it
# to the configured VPS, then restart the systemd service.
#
# Usage:
#   VPS=root@your-vps.example.com ./scripts/deploy.sh
#
# Optional env:
#   ARCH=arm64                  (default: amd64)
#   REMOTE_PATH=/opt/librefy    (default)
#   SERVICE=librefyd            (default)
#
# Pre-requisites on the VPS: the librefy user, /opt/librefy, /var/lib/librefy
# and the systemd unit must already exist. See docs/DEPLOY.md for first-time
# setup.

set -euo pipefail

: "${VPS:?VPS=user@host required (e.g. VPS=root@1.2.3.4 ./scripts/deploy.sh)}"
ARCH="${ARCH:-amd64}"
REMOTE_PATH="${REMOTE_PATH:-/opt/librefy}"
SERVICE="${SERVICE:-librefyd}"

cd "$(dirname "$0")/../backend"

echo "→ building librefyd (linux/${ARCH})…"
CGO_ENABLED=0 GOOS=linux GOARCH="${ARCH}" \
  go build -ldflags="-s -w" -o /tmp/librefyd ./cmd/librefyd

SIZE=$(stat -c%s /tmp/librefyd 2>/dev/null || stat -f%z /tmp/librefyd)
echo "  built: $(numfmt --to=iec "${SIZE}" 2>/dev/null || echo "${SIZE} bytes")"

echo "→ uploading to ${VPS}:${REMOTE_PATH}…"
scp -q /tmp/librefyd "${VPS}:/tmp/librefyd.new"

echo "→ swap + restart…"
ssh "${VPS}" "
  set -e
  mv /tmp/librefyd.new ${REMOTE_PATH}/librefyd
  chmod 755 ${REMOTE_PATH}/librefyd
  systemctl restart ${SERVICE}
  sleep 1
  systemctl status ${SERVICE} --no-pager | head -12
"

rm -f /tmp/librefyd
echo "✓ deployed"
