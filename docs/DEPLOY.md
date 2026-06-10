# Deploying Librefy on a VPS

This walks through hosting your own `librefyd` on a typical Ubuntu/Debian
VPS so the Librefy app can stream tracks from your own catalog.

## What you'll end up with

- A single `librefyd` binary at `/opt/librefy/librefyd`
- SQLite database at `/var/lib/librefy/librefy.db`
- Dedicated `librefy` system user (no shell)
- systemd-managed service on port 8088
- Admin web UI at `http://YOUR_IP:8088/admin/`

The whole thing fits in ~15 MB RAM and a few MB on disk.

---

## 1. Build the binary on your machine

```bash
cd backend
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -ldflags="-s -w" -o librefyd ./cmd/librefyd
```

- `CGO_ENABLED=0` → fully static; runs on any Linux without dependencies.
  We use `modernc.org/sqlite` (pure Go) so this Just Works.
- `-ldflags="-s -w"` → strip symbols. Final binary ≈ 11 MB.
- Use `GOARCH=arm64` for ARM VPS (Oracle Ampere, AWS Graviton, etc.).

## 2. Provision the VPS

```bash
ssh root@YOUR_VPS

# Create a dedicated, login-less user
useradd --system --home /var/lib/librefy --shell /usr/sbin/nologin librefy

mkdir -p /opt/librefy /var/lib/librefy
chown -R librefy:librefy /var/lib/librefy
```

## 3. Upload the binary

From your machine:

```bash
scp librefyd root@YOUR_VPS:/opt/librefy/
ssh root@YOUR_VPS 'chmod +x /opt/librefy/librefyd'
```

## 4. Generate an admin token

The admin API is disabled by default. Generate a strong random token
**on the VPS** and keep it safe:

```bash
openssl rand -hex 32
```

## 5. systemd unit

Save as `/etc/systemd/system/librefyd.service` (replace `<TOKEN>`):

```ini
[Unit]
Description=Librefy backend (libre music metadata API)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=librefy
Group=librefy
WorkingDirectory=/var/lib/librefy
ExecStart=/opt/librefy/librefyd
Restart=on-failure
RestartSec=3

Environment=LIBREFY_ADDR=0.0.0.0:8088
Environment=LIBREFY_DB=/var/lib/librefy/librefy.db
Environment=LIBREFY_ADMIN_TOKEN=<TOKEN>
# Optional: shown in admin UI / used for the in-app deploy hint
# Environment=LIBREFY_PUBLIC_URL=http://YOUR_VPS:8088

# Hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ReadWritePaths=/var/lib/librefy
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
MemoryDenyWriteExecute=true
RestrictRealtime=true

[Install]
WantedBy=multi-user.target
```

```bash
chmod 600 /etc/systemd/system/librefyd.service   # protects the token
systemctl daemon-reload
systemctl enable --now librefyd
systemctl status librefyd
journalctl -u librefyd -f       # live logs
```

## 6. Firewall

```bash
ufw allow 8088/tcp comment 'librefyd public API'
ufw reload
```

## 7. Verify

```bash
curl http://YOUR_VPS:8088/api/v1/health
curl http://YOUR_VPS:8088/api/v1/trending?limit=3
curl -H "X-Admin-Token: YOUR_TOKEN" http://YOUR_VPS:8088/admin/v1/stats
```

Open `http://YOUR_VPS:8088/admin/` in your browser, paste the token, start
adding tracks.

## 8. Point the app

- **At runtime:** Settings → Backend URL → `http://YOUR_VPS:8088` → Apply.
- **For production builds:** rebuild the APK with

  ```bash
  flutter build apk --release \
    --dart-define=LIBREFY_API=http://YOUR_VPS:8088
  ```

For Android in release mode the host must be whitelisted in
[`app/android/app/src/main/res/xml/network_security_config.xml`](../app/android/app/src/main/res/xml/network_security_config.xml)
unless you serve over HTTPS.

---

## Upgrading

```bash
# Build a new binary on your laptop
cd backend
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o librefyd ./cmd/librefyd

# Replace and restart
scp librefyd root@YOUR_VPS:/tmp/librefyd.new
ssh root@YOUR_VPS '
  mv /tmp/librefyd.new /opt/librefy/librefyd &&
  chmod +x /opt/librefy/librefyd &&
  systemctl restart librefyd &&
  systemctl status librefyd --no-pager
'
```

Or use the one-shot script: `VPS=root@YOUR_VPS ./scripts/deploy.sh`.

## Optional: nginx + HTTPS

If you have a domain (`api.example.com` pointing at the VPS), put nginx
in front and switch to HTTPS — Android won't need the cleartext
exception any more.

```nginx
server {
    listen 80;
    server_name api.example.com;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl http2;
    server_name api.example.com;

    ssl_certificate     /etc/letsencrypt/live/api.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8088;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
certbot --nginx -d api.example.com
ufw deny 8088/tcp   # backend reachable only via nginx now
# and bind librefyd to 127.0.0.1:8088 by setting LIBREFY_ADDR=127.0.0.1:8088
```

## Backups

The whole state lives in one file: `/var/lib/librefy/librefy.db`. A nightly
SQLite backup is trivial:

```bash
sqlite3 /var/lib/librefy/librefy.db ".backup '/var/lib/librefy/backups/$(date +%F).db'"
```

You can also pull the catalog as JSON any time via the admin API:

```bash
curl -H "X-Admin-Token: TOKEN" -o tracks.json \
  http://YOUR_VPS:8088/admin/v1/seed/export
```

Commit `tracks.json` to `backend/internal/db/seed/tracks.json` to bake
your catalog into the next binary.
