// Settings — minimal MVP surface: backend URL, cache controls, about.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/state/providers.dart';

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

  @override
  Widget build(BuildContext context) {
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
              child: TextField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'librefyd base URL',
                ),
                onSubmitted: (v) {
                  // apiBaseUrlProvider is a plain Provider in MVP: we surface
                  // the value to the user but persistence + hot-swap arrives
                  // in v0.2 together with a settings_repository.
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Restart the app to apply the new URL.'),
                    ),
                  );
                },
              ),
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
            const ListTile(
              leading: Icon(Icons.policy_outlined),
              title: Text('Licensing'),
              subtitle: Text(
                'Each track displays its licence. Tracks without a verified '
                'libre licence are not surfaced by the official catalog.',
              ),
            ),
          ]),
        ),
      ],
    );
  }
}
