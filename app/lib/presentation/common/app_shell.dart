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
import 'mini_player.dart';
import 'p2p_intro_dialog.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _introScheduled = false;

  static const _destinations = <_Dest>[
    _Dest('/home', Icons.home_outlined, Icons.home_rounded, 'Home'),
    _Dest('/search', Icons.search_outlined, Icons.search_rounded, 'Search'),
    _Dest('/library', Icons.library_music_outlined, Icons.library_music_rounded, 'Library'),
    _Dest('/settings', Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
  ];

  int _indexFor(String location) {
    for (var i = 0; i < _destinations.length; i++) {
      if (location.startsWith(_destinations[i].path)) return i;
    }
    return 0;
  }

  void _scheduleIntroOnce() {
    if (_introScheduled) return;
    _introScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowP2pIntro(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleIntroOnce();

    // Surface playback errors as a snackbar with a copy-to-clipboard
    // action so users can paste the failure into a bug report.
    ref.listen(playbackErrorProvider, (_, next) {
      final err = next.valueOrNull;
      if (err == null) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(err.message, maxLines: 3, overflow: TextOverflow.ellipsis),
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
                onDestinationSelected: (i) => context.go(_destinations[i].path),
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
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
        onDestinationSelected: (i) => context.go(_destinations[i].path),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _Dest {
  const _Dest(this.path, this.icon, this.selectedIcon, this.label);
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
