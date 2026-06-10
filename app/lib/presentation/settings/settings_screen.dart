// Settings — minimal MVP surface:
//   - Backend URL (live-editable, applied immediately by invalidating
//     the API client provider through Riverpod's StateProvider).
//   - Pointer to the in-app self-hosting guide.
//   - About / licensing notice.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/state/locale_provider.dart';
import '../../application/state/providers.dart';
import '../../l10n/app_localizations.dart';
import '../common/p2p_intro_dialog.dart';
import '../common/welcome_intro_dialog.dart';

/// Public repository URL. Shown in Settings → About; tapping the row
/// copies it to the clipboard. We deliberately do NOT pull in
/// url_launcher just for this — that's a whole platform plugin to ship
/// one outbound link, and Play Console flags the package_visibility
/// queries it ships with.
const _kRepoUrl = 'https://github.com/IILLUMINATION/Librefy';

/// Public Telegram channel for project announcements / community chat.
/// Same rationale as [_kRepoUrl] for not using url_launcher.
const _kTelegramUrl = 'https://t.me/librefy';

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

  Future<void> _copyLink(
      BuildContext context, String url, String confirmation) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(confirmation),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _languageLabel(String? code, AppLocalizations l) {
    switch (code) {
      case 'en':
        return l.settingsLanguageEnglish;
      case 'ru':
        return l.settingsLanguageRussian;
      default:
        return l.settingsLanguageSystem;
    }
  }

  Future<void> _pickLanguage(
      BuildContext context, WidgetRef ref, AppLocalizations l) async {
    final current = ref.read(localeProvider)?.languageCode;
    // We need to distinguish "the user picked the 'follow system' radio,
    // which we encode as null" from "the user dismissed the dialog by
    // tapping outside, in which case we change nothing". showDialog<T>
    // returns null on outside-tap; wrap each selection in a one-element
    // list so the discriminator is unambiguous.
    final picked = await showDialog<List<String?>>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: Text(l.settingsLanguage),
          children: [
            RadioListTile<String?>(
              value: null,
              groupValue: current,
              title: Text(l.settingsLanguageSystem),
              onChanged: (v) => Navigator.of(ctx).pop(<String?>[v]),
            ),
            RadioListTile<String?>(
              value: 'en',
              groupValue: current,
              title: Text(l.settingsLanguageEnglish),
              onChanged: (v) => Navigator.of(ctx).pop(<String?>[v]),
            ),
            RadioListTile<String?>(
              value: 'ru',
              groupValue: current,
              title: Text(l.settingsLanguageRussian),
              onChanged: (v) => Navigator.of(ctx).pop(<String?>[v]),
            ),
          ],
        );
      },
    );
    if (picked == null || !context.mounted) return;
    await ref.read(localeProvider.notifier).set(picked.first);
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
    final l = AppLocalizations.of(context)!;
    final currentLocale = ref.watch(localeProvider);
    return CustomScrollView(
      slivers: [
        SliverAppBar.medium(title: Text(l.settingsTitle)),
        SliverList(
          delegate: SliverChildListDelegate.fixed([
            ListTile(
              leading: const Icon(Icons.language_rounded),
              title: Text(l.settingsLanguage),
              subtitle: Text(_languageLabel(currentLocale?.languageCode, l)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _pickLanguage(context, ref, l),
            ),
            const Divider(),
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
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('About Librefy'),
              subtitle: const Text(
                'A privacy-first catalog of freely-redistributable music '
                '(Creative Commons / public-domain). Like Nextcloud for '
                'music: you can use the public catalog, or run your own '
                'librefyd in 10 minutes and own everything end-to-end.',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              // Re-open the full welcome card so existing users (who
              // already dismissed it on first launch) can re-read it.
              // showWelcomeIntroAlways unconditionally pops the dialog
              // without checking the "seen" flag.
              onTap: () => showWelcomeIntroAlways(context),
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
            ListTile(
              leading: const Icon(Icons.code_rounded),
              title: const Text('Source code'),
              subtitle: Text(
                _kRepoUrl,
                style: TextStyle(color: scheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.copy_rounded),
              onTap: () => _copyLink(context, _kRepoUrl,
                  'Repository URL copied to clipboard'),
            ),
            ListTile(
              leading: const Icon(Icons.send_rounded),
              title: const Text('Telegram channel'),
              subtitle: Text(
                _kTelegramUrl,
                style: TextStyle(color: scheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.copy_rounded),
              onTap: () => _copyLink(context, _kTelegramUrl,
                  'Telegram link copied to clipboard'),
            ),
          ]),
        ),
      ],
    );
  }
}
