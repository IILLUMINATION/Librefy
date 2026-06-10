// AppShell is the persistent chrome around every primary screen:
//   - NavigationBar (compact) or NavigationRail (medium+)
//   - MiniPlayer pinned to the bottom whenever something is playing
//
// The shell is responsive: it switches to a navigation rail when the
// window is at least 600dp wide — that's how the Linux desktop build
// gets a desktop-appropriate layout for free.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/audio/audio_providers.dart';
import '../../application/torrent/source_resolver.dart';
import '../../l10n/app_localizations.dart';
import 'mini_player.dart';
import 'p2p_intro_dialog.dart';
import 'privacy_policy_dialog.dart';
import 'welcome_intro_dialog.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _introScheduled = false;

  static const _destPaths = <String>['/home', '/search', '/library', '/settings'];
  static const _destIcons = <IconData>[
    Icons.home_outlined,
    Icons.search_outlined,
    Icons.library_music_outlined,
    Icons.settings_outlined,
  ];
  static const _destIconsSelected = <IconData>[
    Icons.home_rounded,
    Icons.search_rounded,
    Icons.library_music_rounded,
    Icons.settings_rounded,
  ];

  List<String> _destLabels(AppLocalizations l) =>
      [l.navHome, l.navSearch, l.navLibrary, l.navSettings];

  int _indexFor(String location) {
    for (var i = 0; i < _destPaths.length; i++) {
      if (location.startsWith(_destPaths[i])) return i;
    }
    return 0;
  }

  void _scheduleIntroOnce() {
    if (_introScheduled) return;
    _introScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Order matters:
      //   1. Welcome — explains what Librefy is at all, so the privacy
      //      policy and P2P prompts that follow have context. Without
      //      this, brand-new users coming from Play Store see a
      //      half-empty home feed and bounce, mistaking Librefy for
      //      yet-another-broken-Spotify-clone.
      //   2. Privacy policy — gating: must be accepted before any
      //      backend request runs.
      //   3. P2P intro — purely informational; explains why some
      //      tracks may behave differently.
      if (!mounted) return;
      await maybeShowWelcomeIntro(context, ref);
      if (!mounted) return;
      await maybeShowPrivacyPolicy(context, ref);
      if (!mounted) return;
      await maybeShowP2pIntro(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleIntroOnce();
    final l = AppLocalizations.of(context)!;

    // Surface playback errors as a snackbar with a copy-to-clipboard
    // action so users can paste the failure into a bug report.
    ref.listen(playbackErrorProvider, (_, next) {
      final err = next.valueOrNull;
      if (err == null) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      // Localise NoPlayableSourceError; for any other error fall back
      // to its (English, developer-facing) message.
      String displayMsg = err.message;
      final cause = err.cause;
      if (cause is NoPlayableSourceError) {
        switch (cause.kind) {
          case NoPlayableSourceKind.p2pOnlyEngineMissing:
            displayMsg = l.errorP2POnlyEngineMissing;
          case NoPlayableSourceKind.p2pOnlyOpenFailed:
            displayMsg = l.errorP2POnlyOpenFailed;
          case NoPlayableSourceKind.noSource:
            displayMsg = l.errorNoSource;
        }
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content:
                Text(displayMsg, maxLines: 3, overflow: TextOverflow.ellipsis),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Copy log',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: err.toString()));
              },
            ),
          ),
        );
    });

    final location = GoRouterState.of(context).matchedLocation;
    final selected = _indexFor(location);
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    final labels = _destLabels(l);

    final body = Column(
      children: [
        Expanded(child: widget.child),
        const MiniPlayer(),
      ],
    );

    if (isWide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: selected,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (i) => context.go(_destPaths[i]),
                destinations: [
                  for (var i = 0; i < _destPaths.length; i++)
                    NavigationRailDestination(
                      icon: Icon(_destIcons[i]),
                      selectedIcon: Icon(_destIconsSelected[i]),
                      label: Text(labels[i]),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (i) => context.go(_destPaths[i]),
        destinations: [
          for (var i = 0; i < _destPaths.length; i++)
            NavigationDestination(
              icon: Icon(_destIcons[i]),
              selectedIcon: Icon(_destIconsSelected[i]),
              label: labels[i],
            ),
        ],
      ),
    );
  }
}
