// Central Riverpod providers. Hand-written (no riverpod_generator) so
// the MVP compiles without build_runner. Each provider is small and
// single-purpose; widgets depend on the narrowest possible slice.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_base_url_store.dart';
import '../../core/network/api_config.dart';
import '../../data/datasources/librefy_api.dart';
import '../../data/repositories/catalog_repository_impl.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/catalog_repository.dart';

/// SharedPreferences-backed store for the API base URL.
/// Overridden in main.dart with the actual instance once SharedPreferences
/// has been initialised; throws if accessed before that.
final apiBaseUrlStoreProvider = Provider<ApiBaseUrlStore>((ref) {
  throw UnimplementedError('apiBaseUrlStoreProvider must be overridden in main');
});

/// The API base URL the app talks to. Persisted across restarts via
/// [ApiBaseUrlStore]; falls back to [ApiConfig.defaultBaseUrl] when no
/// value has been saved yet (first launch, fresh install).
final apiBaseUrlProvider =
    NotifierProvider<ApiBaseUrlNotifier, String>(ApiBaseUrlNotifier.new);

class ApiBaseUrlNotifier extends Notifier<String> {
  @override
  String build() {
    final store = ref.watch(apiBaseUrlStoreProvider);
    return store.load() ?? ApiConfig.defaultBaseUrl();
  }

  /// Update the URL and persist it.
  Future<void> set(String url) async {
    final v = url.trim();
    if (v.isEmpty || v == state) return;
    state = v;
    await ref.read(apiBaseUrlStoreProvider).save(v);
  }

  /// Reset to the build-time default and forget the saved value.
  Future<void> resetToDefault() async {
    state = ApiConfig.defaultBaseUrl();
    await ref.read(apiBaseUrlStoreProvider).clear();
  }
}

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
