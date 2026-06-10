// First-launch P2P explainer.
//
// Shown once the first time the user runs a build that has the native
// libtorrent bridge available. The user can read what's happening and
// either keep P2P enabled (default) or opt out. The choice is persisted
// in SharedPreferences and respected by SourceResolver.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSeenKey = 'librefy.p2p.introSeen.v1';
const _kEnabledKey = 'librefy.p2p.enabled.v1';

/// Whether the user has explicitly enabled P2P delivery. Defaults to
/// true (we want it on out of the box), but the dialog gives them the
/// chance to flip it off.
final p2pEnabledProvider = StateProvider<bool>((ref) => true);

/// Loads persisted flags. Wire this into main() bootstrap.
Future<({bool seen, bool enabled})> loadP2pFlags() async {
  final prefs = await SharedPreferences.getInstance();
  return (
    seen: prefs.getBool(_kSeenKey) ?? false,
    enabled: prefs.getBool(_kEnabledKey) ?? true,
  );
}

Future<void> _saveFlags({required bool seen, required bool enabled}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kSeenKey, seen);
  await prefs.setBool(_kEnabledKey, enabled);
}

/// Shows the intro modal if it hasn't been shown before in this install.
/// Idempotent: safe to call on every app start.
Future<void> maybeShowP2pIntro(BuildContext context, WidgetRef ref) async {
  final flags = await loadP2pFlags();
  ref.read(p2pEnabledProvider.notifier).state = flags.enabled;
  if (flags.seen || !context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _IntroDialog(initialEnabled: flags.enabled),
  );
}

class _IntroDialog extends ConsumerStatefulWidget {
  const _IntroDialog({required this.initialEnabled});
  final bool initialEnabled;
  @override
  ConsumerState<_IntroDialog> createState() => _IntroDialogState();
}

class _IntroDialogState extends ConsumerState<_IntroDialog> {
  late bool _enabled = widget.initialEnabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: const Icon(Icons.share_rounded, size: 32),
      title: const Text('Peer-assisted streaming'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Librefy can play tracks delivered through peers instead of '
            "downloading every byte from a server. It's faster on busy "
            "networks and respects the project's lightweight backend ethic.",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'What this means in practice:',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          const _Bullet('Some tracks open from a swarm via libtorrent.'),
          const _Bullet('Your device temporarily shares those pieces back.'),
          const _Bullet(
              'Only tracks the operator marked as libre/CC are eligible.'),
          const _Bullet('Disk + bandwidth usage is bounded; see Settings.'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable peer delivery'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () async {
            await _saveFlags(seen: true, enabled: _enabled);
            ref.read(p2pEnabledProvider.notifier).state = _enabled;
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Continue'),
        ),
      ],
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
