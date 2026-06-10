// User library: per-device persistent state for playlists & liked tracks.
//
// Privacy-first design: nothing here is ever sent to the backend.
// We store the FULL Track payload (not just the ID) so that even if the
// upstream catalog disappears the user keeps their library readable.
//
// Storage: a single SharedPreferences JSON blob. It's tiny (few KB even
// with hundreds of tracks) and keeps the dependency surface flat.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/license.dart';
import '../../domain/entities/track.dart';

const _kKey = 'librefy.userLibrary.v1';

/// Special playlist id that always exists. Hidden in the "manage" list,
/// surfaced as a top-level entry in the UI.
const kLikedPlaylistId = '__liked__';

class UserPlaylist {
  UserPlaylist({
    required this.id,
    required this.name,
    required this.trackIds,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String name;
  final List<String> trackIds;
  final DateTime createdAt;

  UserPlaylist copyWith({String? name, List<String>? trackIds}) =>
      UserPlaylist(
        id: id,
        name: name ?? this.name,
        trackIds: trackIds ?? this.trackIds,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'createdAt': createdAt.toIso8601String(),
      };

  static UserPlaylist fromJson(Map<String, dynamic> j) => UserPlaylist(
        id: j['id'] as String,
        name: j['name'] as String,
        trackIds: (j['trackIds'] as List).cast<String>(),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// All persistent user-library state. Immutable; mutate via the notifier.
class UserLibrary {
  const UserLibrary({
    required this.playlists,
    required this.tracksById,
  });

  /// All user playlists, including the synthetic Liked one (id == kLikedPlaylistId).
  final List<UserPlaylist> playlists;

  /// Snapshot of every Track we've ever liked or added to a playlist,
  /// keyed by its namespaced ID. Lets the Library tab render even if
  /// the upstream catalog is offline.
  final Map<String, Track> tracksById;

  UserPlaylist? get liked =>
      playlists.firstWhere((p) => p.id == kLikedPlaylistId,
          orElse: () => UserPlaylist(id: kLikedPlaylistId, name: 'Liked', trackIds: []));

  List<UserPlaylist> get userPlaylists =>
      playlists.where((p) => p.id != kLikedPlaylistId).toList();

  bool isLiked(String trackId) =>
      liked?.trackIds.contains(trackId) ?? false;

  /// Resolve a track id to a Track. Returns null if we have no record.
  Track? trackFor(String id) => tracksById[id];

  static const empty = UserLibrary(playlists: [], tracksById: {});

  Map<String, dynamic> toJson() => {
        'playlists': playlists.map((p) => p.toJson()).toList(),
        'tracks': tracksById.map((k, v) => MapEntry(k, _trackToJson(v))),
      };

  static UserLibrary fromJson(Map<String, dynamic> j) {
    final pls = (j['playlists'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(UserPlaylist.fromJson)
        .toList();
    final tracksRaw = (j['tracks'] as Map? ?? {}).cast<String, dynamic>();
    final tracks = tracksRaw.map(
      (k, v) => MapEntry(k, _trackFromJson(v as Map<String, dynamic>)),
    );

    // Always make sure the Liked synthetic playlist exists.
    if (!pls.any((p) => p.id == kLikedPlaylistId)) {
      pls.insert(
          0, UserPlaylist(id: kLikedPlaylistId, name: 'Liked', trackIds: []));
    }
    return UserLibrary(playlists: pls, tracksById: tracks);
  }
}

Map<String, dynamic> _trackToJson(Track t) => {
      'id': t.id,
      'title': t.title,
      'artist': t.artist,
      'album': t.album,
      'durationMs': t.duration.inMilliseconds,
      'artworkUrl': t.artworkUrl,
      'streamUrl': t.streamUrl,
      'magnet': t.magnet,
      'infoHash': t.infoHash,
      'license': {
        'code': t.license.code,
        'name': t.license.name,
        'url': t.license.url,
      },
      'attribution': t.attribution,
      'tags': t.tags,
      'provider': t.provider,
    };

Track _trackFromJson(Map<String, dynamic> j) {
  final lic = (j['license'] as Map?)?.cast<String, dynamic>() ?? const {};
  return Track(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    artist: j['artist'] as String? ?? '',
    album: j['album'] as String?,
    duration: Duration(milliseconds: (j['durationMs'] as num?)?.toInt() ?? 0),
    artworkUrl: j['artworkUrl'] as String?,
    streamUrl: j['streamUrl'] as String?,
    magnet: j['magnet'] as String?,
    infoHash: j['infoHash'] as String?,
    license: License(
      code: lic['code'] as String? ?? 'UNKNOWN',
      name: lic['name'] as String? ?? 'Unknown',
      url: lic['url'] as String?,
    ),
    attribution: j['attribution'] as String?,
    tags: (j['tags'] as List?)?.cast<String>() ?? const [],
    provider: j['provider'] as String? ?? 'unknown',
  );
}

class UserLibraryNotifier extends Notifier<UserLibrary> {
  late SharedPreferences _prefs;

  @override
  UserLibrary build() {
    _prefs = ref.watch(_sharedPrefsProvider);
    final raw = _prefs.getString(_kKey);
    if (raw == null) {
      return UserLibrary.fromJson(const {}); // creates Liked
    }
    try {
      return UserLibrary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return UserLibrary.fromJson(const {});
    }
  }

  Future<void> _persist(UserLibrary next) async {
    state = next;
    await _prefs.setString(_kKey, jsonEncode(next.toJson()));
  }

  /// Like / unlike a track. Returns the new liked state.
  Future<bool> toggleLike(Track t) async {
    final lib = state;
    final liked = lib.liked!;
    final now = List<String>.from(liked.trackIds);
    final tracksById = Map<String, Track>.from(lib.tracksById);
    bool isLiked;
    if (now.contains(t.id)) {
      now.remove(t.id);
      isLiked = false;
    } else {
      now.insert(0, t.id);
      tracksById[t.id] = t;
      isLiked = true;
    }
    final updatedLiked = liked.copyWith(trackIds: now);
    final pls = [
      for (final p in lib.playlists)
        if (p.id == kLikedPlaylistId) updatedLiked else p,
    ];
    await _persist(UserLibrary(playlists: pls, tracksById: tracksById));
    return isLiked;
  }

  Future<UserPlaylist> createPlaylist(String name) async {
    final lib = state;
    final id = 'pl-${DateTime.now().microsecondsSinceEpoch}';
    final p = UserPlaylist(id: id, name: name.trim(), trackIds: []);
    await _persist(UserLibrary(
      playlists: [...lib.playlists, p],
      tracksById: lib.tracksById,
    ));
    return p;
  }

  Future<void> renamePlaylist(String id, String newName) async {
    final lib = state;
    final pls = [
      for (final p in lib.playlists)
        if (p.id == id) p.copyWith(name: newName.trim()) else p,
    ];
    await _persist(UserLibrary(playlists: pls, tracksById: lib.tracksById));
  }

  Future<void> deletePlaylist(String id) async {
    if (id == kLikedPlaylistId) return; // can't delete Liked
    final lib = state;
    final pls = lib.playlists.where((p) => p.id != id).toList();
    await _persist(UserLibrary(playlists: pls, tracksById: lib.tracksById));
  }

  /// Add a track to [playlistId]; idempotent. Persists the full Track
  /// payload too so the library is offline-safe.
  Future<void> addTrackToPlaylist(String playlistId, Track t) async {
    final lib = state;
    final pls = [
      for (final p in lib.playlists)
        if (p.id == playlistId && !p.trackIds.contains(t.id))
          p.copyWith(trackIds: [...p.trackIds, t.id])
        else
          p,
    ];
    final tracksById = Map<String, Track>.from(lib.tracksById)..[t.id] = t;
    await _persist(UserLibrary(playlists: pls, tracksById: tracksById));
  }

  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final lib = state;
    final pls = [
      for (final p in lib.playlists)
        if (p.id == playlistId)
          p.copyWith(trackIds: p.trackIds.where((id) => id != trackId).toList())
        else
          p,
    ];
    await _persist(UserLibrary(playlists: pls, tracksById: lib.tracksById));
  }
}

/// Overridden in main.dart with the real SharedPreferences instance.
final _sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
      'sharedPreferencesProvider must be overridden in main');
});

/// Public alias so other code overrides this name.
final sharedPreferencesProvider = _sharedPrefsProvider;

final userLibraryProvider =
    NotifierProvider<UserLibraryNotifier, UserLibrary>(UserLibraryNotifier.new);
