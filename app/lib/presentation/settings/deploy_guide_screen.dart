// In-app mini-guide for self-hosting the Librefy backend.
//
// Why this lives in the app instead of just the README:
//   - Librefy is privacy-first and the default public catalog is small.
//     The fastest path to "your own music collection" is to run librefyd
//     on your own machine or VPS.
//   - We want users to discover this without needing to leave the app.
//   - Each command is copy-buttoned so even non-CLI-fluent users have
//     a shot at getting it running.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DeployGuideScreen extends StatelessWidget {
  const DeployGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deploy your own backend')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: const [
          _Intro(),
          _Step(
            number: 1,
            title: 'Get the source',
            body:
                'Clone the public repo. Everything needed for a one-binary '
                'deployment is in the backend/ folder.',
            commands: [
              _Cmd('git clone https://github.com/IILLUMINATION/Librefy.git'),
              _Cmd('cd Librefy/backend'),
            ],
          ),
          _Step(
            number: 2,
            title: 'Build a static binary',
            body:
                'A single Go binary, no runtime dependencies. Works for any '
                'Linux x86_64 server. Requires Go 1.22+.',
            commands: [
              _Cmd(
                'CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \\\n'
                '  go build -ldflags="-s -w" -o librefyd ./cmd/librefyd',
              ),
            ],
          ),
          _Step(
            number: 3,
            title: 'Ship it to your VPS',
            body:
                'Place the binary somewhere stable and create a data directory '
                'for the SQLite database. The DB file is created automatically '
                'on first run, you do not need to seed it manually.',
            commands: [
              _Cmd('scp librefyd root@YOUR_VPS:/opt/librefy/'),
              _Cmd(
                'ssh root@YOUR_VPS \'\n'
                '  useradd --system --home /var/lib/librefy --shell /usr/sbin/nologin librefy || true\n'
                '  mkdir -p /opt/librefy /var/lib/librefy\n'
                '  chown librefy:librefy /var/lib/librefy\n'
                '  chmod +x /opt/librefy/librefyd\n'
                "'",
              ),
            ],
          ),
          _Step(
            number: 4,
            title: 'Generate an admin token',
            body:
                'The /admin surface (web UI + write API) stays disabled until '
                'you set LIBREFY_ADMIN_TOKEN. Generate a strong random value '
                'and save it — you will paste it into the web UI in step 7.',
            commands: [
              _Cmd('openssl rand -hex 32'),
            ],
          ),
          _Step(
            number: 5,
            title: 'Install a systemd unit',
            body:
                'This keeps librefyd running and starts it on boot. Replace '
                'YOUR_TOKEN with the value from step 4, and YOUR_VPS_IP with '
                "your server's public address.",
            commands: [
              _Cmd(
                'sudo tee /etc/systemd/system/librefyd.service > /dev/null <<EOF\n'
                '[Unit]\n'
                'Description=Librefy backend\n'
                'After=network-online.target\n'
                'Wants=network-online.target\n'
                '\n'
                '[Service]\n'
                'User=librefy\n'
                'Group=librefy\n'
                'WorkingDirectory=/var/lib/librefy\n'
                'ExecStart=/opt/librefy/librefyd\n'
                'Environment=LIBREFY_ADDR=0.0.0.0:8080\n'
                'Environment=LIBREFY_DB=/var/lib/librefy/librefy.db\n'
                'Environment=LIBREFY_ADMIN_TOKEN=YOUR_TOKEN\n'
                'Environment=LIBREFY_PUBLIC_URL=http://YOUR_VPS_IP:8080\n'
                'Restart=on-failure\n'
                'RestartSec=2s\n'
                '\n'
                '[Install]\n'
                'WantedBy=multi-user.target\n'
                'EOF',
              ),
              _Cmd(
                'sudo systemctl daemon-reload && \\\n'
                '  sudo systemctl enable --now librefyd && \\\n'
                '  sudo systemctl status librefyd --no-pager',
              ),
            ],
            note:
                "If you change LIBREFY_ADDR, open that port in your VPS "
                "provider's firewall as well (Hetzner Cloud Firewall, AWS "
                'Security Group, ufw, etc.).',
          ),
          _Step(
            number: 6,
            title: 'Point this app at your backend',
            body:
                'Open Settings → Backend and paste your URL:',
            commands: [
              _Cmd('http://YOUR_VPS_IP:8080'),
            ],
            note:
                "For production you should sit librefyd behind nginx (or "
                "Caddy) with a Let's Encrypt certificate so the app can "
                'talk over HTTPS — Android blocks plain HTTP to arbitrary '
                'hosts by default. See docs/DEPLOY.md in the repo for the '
                'full HTTPS setup.',
          ),
          _Step(
            number: 7,
            title: 'Add your music',
            body:
                'Open the admin web UI in a browser and paste your token:',
            commands: [
              _Cmd('http://YOUR_VPS_IP:8080/admin/'),
            ],
            note:
                'From the admin UI you can create tracks, build playlists, '
                'bulk-import JSON and export the whole catalog back to a '
                'seed file for git. The token is sent as X-Admin-Token (or '
                'Authorization: Bearer …) on every admin API call — the UI '
                'wires that for you.',
          ),
          SizedBox(height: 24),
          _LegalReminder(),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHigh,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_upload_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Run your own Librefy server',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'The backend is a single ~15 MB Go binary plus a SQLite file. '
              'It fits on the smallest VPS. Follow the steps below and you '
              'will have your own catalog reachable from this app in 5–10 '
              'minutes.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    required this.commands,
    this.note,
  });
  final int number;
  final String title;
  final String body;
  final List<_Cmd> commands;
  final String? note;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    child: Text(
                      '$number',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(body, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 10),
              for (final c in commands) c,
              if (note != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer.withValues(alpha: .4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: scheme.onTertiaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          note!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onTertiaryContainer,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Cmd extends StatelessWidget {
  const _Cmd(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: SelectableText(
                  text,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalReminder extends StatelessWidget {
  const _LegalReminder();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gavel_outlined,
              color: scheme.onErrorContainer, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Only add tracks you have the right to redistribute '
              '(Creative Commons, public-domain, artist-released). '
              'See docs/LEGAL.md in the repo.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
