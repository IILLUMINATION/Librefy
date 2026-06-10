// Settings — minimal MVP surface:
//   - Backend URL (live-editable, applied immediately by invalidating
//     the API client provider through Riverpod's StateProvider).
//   - Pointer to the in-app self-hosting guide.
//   - About / licensing notice.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/state/providers.dart';
import '../common/p2p_intro_dialog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: ref.read(apiBaseUrlProvider));
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyUrl() async {
    final v = _urlCtrl.text.trim();
    if (v.isEmpty) return;
    await ref.read(apiBaseUrlProvider.notifier).set(v);
    // Drop cached repository / API client so the next fetch goes to the
    // new origin.
    ref.invalidate(catalogRepositoryProvider);
    ref.invalidate(featuredPlaylistsProvider);
    ref.invalidate(trendingTracksProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved: $v')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      slivers: [
        const SliverAppBar.medium(title: Text('Settings')),
        SliverList(
          delegate: SliverChildListDelegate.fixed([
            const ListTile(
              title: Text('Backend'),
              subtitle: Text('Where this app fetches metadata from.'),
              dense: true,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlCtrl,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'librefyd base URL',
                        hintText: 'http://192.168.1.10:8088',
                      ),
                      onSubmitted: (_) => _applyUrl(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _applyUrl,
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('Deploy your own backend'),
              subtitle: const Text(
                'Run librefyd on a VPS in ~10 minutes.',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/settings/deploy'),
            ),
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.share_rounded),
              title: const Text('Peer-assisted streaming'),
              subtitle: const Text(
                'Play magnet-linked libre tracks directly from peers.',
              ),
              value: ref.watch(p2pEnabledProvider),
              onChanged: (v) async {
                ref.read(p2pEnabledProvider.notifier).state = v;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('librefy.p2p.enabled.v1', v);
              },
            ),
            const Divider(),
            const ListTile(
              leading: Icon(Icons.info_outline_rounded),
              title: Text('About Librefy'),
              subtitle: Text(
                'Privacy-first, libre/free music streaming. '
                'Catalog limited to Creative Commons / public-domain content.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.policy_outlined),
              title: const Text('Licensing'),
              subtitle: Text(
                'Each track displays its licence. Tracks without a verified '
                'libre licence are not surfaced by the official catalog.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}
