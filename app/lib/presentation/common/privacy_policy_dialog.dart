// First-launch privacy policy acceptance gate.
//
// Shown unconditionally on first launch (and again whenever the policy
// version bumps). The user must either accept or quit — there is no
// "skip" path, because Librefy talks to a network backend and the user
// deserves to know what leaves their device before any request is made.
//
// The accepted policy version is persisted in SharedPreferences. Bumping
// [_kCurrentVersion] in code re-prompts every install on next launch.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';

const _kAcceptedVersionKey = 'librefy.privacy.acceptedVersion.v1';

/// Current policy revision. Increment when the wording materially
/// changes so existing installs see the prompt again.
const int _kCurrentVersion = 1;

/// Shows the privacy policy dialog if the user hasn't already accepted
/// the current revision. Returns once the user has either accepted
/// (proceeds normally) or chosen to exit (in which case the app is
/// already being torn down).
///
/// Idempotent: safe to call on every app start.
Future<void> maybeShowPrivacyPolicy(
    BuildContext context, WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  final accepted = prefs.getInt(_kAcceptedVersionKey) ?? 0;
  if (accepted >= _kCurrentVersion) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _PolicyDialog(),
  );
}

class _PolicyDialog extends ConsumerStatefulWidget {
  const _PolicyDialog();
  @override
  ConsumerState<_PolicyDialog> createState() => _PolicyDialogState();
}

class _PolicyDialogState extends ConsumerState<_PolicyDialog> {
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kAcceptedVersionKey, _kCurrentVersion);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _quit() async {
    // SystemNavigator.pop() closes the current activity / window on
    // every platform Flutter targets (Android finishes the activity,
    // iOS is a no-op per Apple HIG, desktop closes the top window).
    // We deliberately do NOT persist acceptance — next launch will
    // re-prompt.
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = AppLocalizations.of(context)!;
    return PopScope(
      // Block hardware/system back gestures — the user must make an
      // explicit choice.
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.privacy_tip_outlined, size: 32),
        title: Text(l.privacyTitle),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.privacyIntro, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
                Text(l.privacyDontCollectTitle,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                _Bullet(l.privacyDontCollect1),
                _Bullet(l.privacyDontCollect2),
                _Bullet(l.privacyDontCollect3),
                const SizedBox(height: 12),
                Text(l.privacyServerTitle,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                _Bullet(l.privacyServer1),
                _Bullet(l.privacyServer2),
                _Bullet(l.privacyServer3),
                const SizedBox(height: 12),
                Text(l.privacyP2PTitle, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                _Bullet(l.privacyP2P1),
                _Bullet(l.privacyP2P2),
                _Bullet(l.privacyP2P3),
                const SizedBox(height: 12),
                Text(l.privacyLocalTitle,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                _Bullet(l.privacyLocal),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(l.privacyAcceptHint,
                      style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : _quit,
            child: Text(l.privacyExit),
          ),
          FilledButton(
            onPressed: _busy ? null : _accept,
            child: Text(l.privacyAccept),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
