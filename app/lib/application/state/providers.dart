// Central Riverpod providers. Hand-written (no riverpod_generator) so
// the MVP compiles without build_runner. Each provider is small and
// single-purpose; widgets depend on the narrowest possible slice.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_config.dart';
import '../../data/datasources/librefy_api.dart';
import '../../data/repositories/catalog_repository_impl.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/catalog_repository.dart';

/// API base URL — the user can override it from Settings at runtime.
/// We seed it with the build-time default (Android emulator host on
/// Android, 127.0.0.1 elsewhere; see ApiConfig).
final apiBaseUrlProvider =
    StateProvider<String>((ref) => ApiConfig.defaultBaseUrl());

final _apiProvider = Provider<LibrefyApi>((ref) {
  final base = ref.watch(apiBaseUrlProvider);
  return LibrefyApi.withBaseUrl(base);
});

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepositoryImpl(ref.watch(_apiProvider));
});

/// Featured playlists for the home screen.
final featuredPlaylistsProvider = FutureProvider<List<Playlist>>((ref) {
  return ref.watch(catalogRepositoryProvider).featured();
});

/// Trending tracks for the home screen.
final trendingTracksProvider = FutureProvider<List<Track>>((ref) {
  return ref.watch(catalogRepositoryProvider).trending();
});

/// Current search query (debounced by the search screen widget).
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Auto-disposing search results that follow [searchQueryProvider].
final searchResultsProvider = FutureProvider.autoDispose<SearchResult>((ref) async {
  final q = ref.watch(searchQueryProvider).trim();
  if (q.isEmpty) return const SearchResult();
  // Cooperative cancellation: the next query disposes the previous future.
  return ref.watch(catalogRepositoryProvider).search(q);
});

/// Detail of a specific playlist with its tracks.
final playlistDetailProvider = FutureProvider.autoDispose
    .family<({Playlist playlist, List<Track> tracks}), String>((ref, id) {
  return ref.watch(catalogRepositoryProvider).getPlaylist(id);
});

/// Locally maintained "recently played" list (per-device, anonymous).
final recentlyPlayedProvider =
    StateNotifierProvider<RecentlyPlayedNotifier, List<Track>>((ref) {
  return RecentlyPlayedNotifier();
});

/// Privacy-first, in-memory recently-played store. Persistence to disk
/// can be added later; the API surface stays the same.
class RecentlyPlayedNotifier extends StateNotifier<List<Track>> {
  RecentlyPlayedNotifier() : super(const []);

  static const _maxItems = 50;

  void push(Track t) {
    final filtered = state.where((x) => x.id != t.id).toList()..insert(0, t);
    if (filtered.length > _maxItems) {
      filtered.removeRange(_maxItems, filtered.length);
    }
    state = filtered;
  }
}
