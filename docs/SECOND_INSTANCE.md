# Running a second librefyd instance on the same VPS

This is the scenario most Librefy operators reach for after a while: one
public instance for the official / Play-Store-facing catalogue, and a
second private instance for *your* music collection — the "Nextcloud
for music" use case the project was originally built for.

Both run on the same VPS, separate ports, separate databases, separate
admin tokens. They are completely independent at runtime; nothing in
one instance leaks into the other.

This guide assumes you already followed [`DEPLOY.md`](./DEPLOY.md) and
have a working `librefyd.service` on, say, port `8088`. We'll add a
second one called `librefyd-personal.service` on port `8089`.

## 1. Pick a port and confirm it's free

```bash
ss -tln | grep -E ':8089|:8090|:8091'
```

If your chosen port shows up, pick another one. Anything in the
`8080–9000` range that isn't already used is fine. The rest of this
guide assumes `:8089`.

## 2. Provision a separate system user and data directory

Keeping the personal instance under its own UNIX user means a misconfigured
permission can never cross-contaminate the two databases.

```bash
sudo mkdir -p /opt/librefy-personal /var/lib/librefy-personal
sudo useradd --system \
  --home /var/lib/librefy-personal \
  --shell /usr/sbin/nologin \
  librefy-personal || true
sudo chown -R librefy-personal:librefy-personal /var/lib/librefy-personal
```

## 3. Re-use the binary you already have

There is no need to rebuild — `librefyd` is a single static Go binary
and the two instances will run as different processes with different
env vars.

```bash
sudo cp -f /opt/librefy/librefyd /opt/librefy-personal/librefyd
sudo chmod +x /opt/librefy-personal/librefyd
sudo chown librefy-personal:librefy-personal /opt/librefy-personal/librefyd
```

When you rebuild later (`go build ... -o /opt/librefy/librefyd`),
re-run that one `cp` line and `systemctl restart librefyd-personal`
to ship the new binary into the second instance too.

## 4. Generate a fresh admin token

The admin token gates the `/admin/*` write API and the bundled web UI.
**Do NOT reuse the token from your public instance** — if either token
ever leaks, you only want one instance compromised.

```bash
openssl rand -hex 32
```

Copy the output, you'll paste it into the unit file in the next step.

## 5. Install a separate systemd unit

```bash
sudo tee /etc/systemd/system/librefyd-personal.service > /dev/null <<'EOF'
[Unit]
Description=Librefy backend (personal instance)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=librefy-personal
Group=librefy-personal
WorkingDirectory=/var/lib/librefy-personal
ExecStart=/opt/librefy-personal/librefyd
Restart=on-failure
RestartSec=3

Environment=LIBREFY_ADDR=0.0.0.0:8089
Environment=LIBREFY_DB=/var/lib/librefy-personal/librefy.db
Environment=LIBREFY_ADMIN_TOKEN=PASTE_YOUR_TOKEN_HERE
Environment=LIBREFY_PUBLIC_URL=http://YOUR_VPS_IP:8089

# Sandboxing — same posture as the public instance.
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/lib/librefy-personal
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF
```

Replace `PASTE_YOUR_TOKEN_HERE` with the token from step 4, and
`YOUR_VPS_IP` with your actual public IP (or a hostname like
`mymusic.example.com` once you've set up HTTPS — see step 8).

Reload and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now librefyd-personal
sudo systemctl status librefyd-personal --no-pager
```

You should see `Active: active (running)` and a line like
`librefyd listening addr=0.0.0.0:8089` in the journal.

## 6. Open the port in the firewall

UFW:

```bash
sudo ufw allow 8089/tcp comment 'librefyd personal instance'
```

If you're on a managed VPS (Hetzner Cloud, AWS, Vultr) you'll also
need to open the port in the *provider's* firewall console — UFW alone
isn't enough there.

## 7. Point the Librefy app at the new instance

In the mobile app:

1. **Settings → Backend → URL** → paste `http://YOUR_VPS_IP:8089`
2. Tap **Apply**.

The app immediately drops the cached repository and starts fetching
from your new backend. Library / playlists / likes are stored per-backend
in app-local storage, so switching the URL back to the public instance
restores your public-instance state untouched.

## 8. Add HTTPS (strongly recommended)

Android (target SDK 28+) blocks plain HTTP to arbitrary hosts by default.
Plain HTTP works in development, but once you publish your app or run
a public link, you need TLS.

The simplest layout is a single nginx in front of *both* instances on
different subdomains:

```nginx
# /etc/nginx/sites-available/librefy
server {
  listen 443 ssl;
  server_name librefy.example.com;
  ssl_certificate     /etc/letsencrypt/live/librefy.example.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/librefy.example.com/privkey.pem;

  client_max_body_size 200M;       # tracks
  proxy_read_timeout   3600s;      # admin uploads can be slow

  location / {
    proxy_pass         http://127.0.0.1:8088;
    proxy_set_header   Host              $host;
    proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header   X-Forwarded-Proto https;
  }
}

server {
  listen 443 ssl;
  server_name mymusic.example.com;
  ssl_certificate     /etc/letsencrypt/live/mymusic.example.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/mymusic.example.com/privkey.pem;

  client_max_body_size 200M;
  proxy_read_timeout   3600s;

  location / {
    proxy_pass         http://127.0.0.1:8089;
    proxy_set_header   Host              $host;
    proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header   X-Forwarded-Proto https;
  }
}
```

Then `certbot --nginx -d librefy.example.com -d mymusic.example.com`
gets you certificates and reload nginx. After this you can close
`8088/tcp` and `8089/tcp` in UFW — only `443` needs to be open to
the world.

## 9. Add your music

Open the admin UI in a browser:

```
http://YOUR_VPS_IP:8089/admin/
```

Paste the token from step 4, and you can:

- create tracks (paste a streamUrl, a magnet, or both),
- build playlists (curated → home feed, regular → just listed),
- bulk-import a JSON seed file (one-shot for migrating a library),
- export the whole catalogue back to JSON (commit it to a private git
  repo for backups).

The token is sent as `X-Admin-Token` (or `Authorization: Bearer …`) on
every admin API call — the embedded UI wires that up for you.

## Operational notes

- **Backups.** SQLite is one file: `/var/lib/librefy-personal/librefy.db`.
  Add it to your existing rsync / restic / borg job and you're set.
  Stop the unit first (`systemctl stop librefyd-personal`) if you want
  a clean snapshot; live copies work too because SQLite uses WAL.
- **Logs.** `journalctl -u librefyd-personal -e -f` for live, `-n 200`
  for last batch. No log file on disk; everything goes to journald.
- **Upgrades.** Rebuild the binary, `cp` over `/opt/librefy-personal/librefyd`,
  `systemctl restart librefyd-personal`. Database migrations run
  automatically on start; downgrades aren't supported.
- **Resource ceiling.** Each instance is ~20 MB RSS idle. A 1 GB / 1 vCPU
  VPS comfortably hosts 5+ of them — the bottleneck is bandwidth, not
  CPU or RAM.
