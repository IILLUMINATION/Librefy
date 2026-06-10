// First-launch "what is Librefy" explainer.
//
// Why this exists: Librefy is a niche product (think "Nextcloud for
// music, restricted to CC / public-domain catalogues") and a brand-new
// user opening it on Play Store has no context. Without this card,
// the home feed looks like a generic, half-empty music player and
// users churn before they understand what's going on.
//
// Shown exactly once per install (and re-shown if [_kCurrentVersion]
// is bumped). The card describes:
//   1. What Librefy is — a curated catalogue of freely redistributable
//      music, not a substitute for Spotify.
//   2. Why the catalogue is small on day one — only verified-libre
//      tracks land in the default backend.
//   3. The escape hatch: anyone can run their own librefyd and have
//      a private catalogue with their own library.
//
// This dialog is purely informational; we don't gate anything behind
// it (the privacy policy gate is a separate dialog). Acknowledging
// just marks "seen" in SharedPreferences and disappears.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSeenVersionKey = 'librefy.welcomeIntro.seenVersion.v1';
const int _kCurrentVersion = 1;

/// Shows the welcome intro if the user hasn't seen the current version.
/// Idempotent; safe to call on every cold start.
Future<void> maybeShowWelcomeIntro(
    BuildContext context, WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  final seen = prefs.getInt(_kSeenVersionKey) ?? 0;
  if (seen >= _kCurrentVersion) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _WelcomeDialog(),
  );
}

/// Forces the welcome dialog open regardless of the "seen" flag.
/// Wired into Settings → About Librefy so a returning user can re-read
/// the project pitch without uninstalling.
Future<void> showWelcomeIntroAlways(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _WelcomeDialog(),
  );
}

class _WelcomeDialog extends StatelessWidget {
  const _WelcomeDialog();

  Future<void> _markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSeenVersionKey, _kCurrentVersion);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopScope(
      // Force an explicit tap so the user actually reads the body before
      // dismissing. Hitting back on a barrierDismissible:false dialog
      // would otherwise close it silently.
      canPop: false,
      child: AlertDialog(
        icon: Icon(Icons.music_note_rounded, size: 32, color: scheme.primary),
        title: const Text('Welcome to Librefy'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Librefy isn't another Spotify clone — there's no "
                  'commercial catalogue here, and there never will be. '
                  'Think of it as a niche, self-hostable player for '
                  'music that is genuinely free to redistribute.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                _Bullet(
                  icon: Icons.verified_outlined,
                  title: 'Libre by default',
                  body:
                      "Every track in the official catalogue is Creative "
                      'Commons or public-domain. Nothing else gets surfaced.',
                ),
                _Bullet(
                  icon: Icons.lock_outline_rounded,
                  title: 'Privacy-first',
                  body:
                      "No accounts, no ads, no third-party analytics. "
                      "What's collected is spelled out in the privacy "
                      'policy on the next screen.',
                ),
                _Bullet(
                  icon: Icons.cloud_outlined,
                  title: 'Self-hostable',
                  body:
                      'Like Nextcloud for music: the backend is a single '
                      "Go binary. Run librefyd on your own VPS, point this "
                      'app at it (Settings → Backend) and your catalogue '
                      'is yours.',
                ),
                _Bullet(
                  icon: Icons.share_rounded,
                  title: 'Peer-assisted (optional)',
                  body:
                      'Some tracks stream from a libtorrent swarm instead '
                      'of a server. You can turn this off in Settings.',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "The default catalogue is intentionally small — only "
                    "verified-libre tracks land there. If you want a full "
                    'personal library, point this app at your own librefyd '
                    '(Settings → Deploy your own backend).',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              await _markSeen();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
