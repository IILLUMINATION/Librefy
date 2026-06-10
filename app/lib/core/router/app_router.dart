// App-wide navigation. We use go_router because:
//   - URL-based routing makes deep-linking trivial later.
//   - The desktop build benefits from a real address bar / history.
//
// The shell route hosts the bottom navigation (mobile) or navigation rail
// (desktop) and keeps the mini-player permanently mounted at the bottom.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/common/app_shell.dart';
import '../../presentation/home/home_screen.dart';
import '../../presentation/library/library_screen.dart';
import '../../presentation/library/playlist_detail_screen.dart';
import '../../presentation/player/now_playing_screen.dart';
import '../../presentation/search/search_screen.dart';
import '../../presentation/settings/settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
          GoRoute(path: '/library', builder: (_, __) => const LibraryScreen()),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
          GoRoute(
            path: '/playlist/:id',
            builder: (context, state) => PlaylistDetailScreen(
              id: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/now-playing',
        builder: (_, __) => const NowPlayingScreen(),
      ),
    ],
  );
});
