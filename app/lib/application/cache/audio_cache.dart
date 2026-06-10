// On-disk LRU cache for streamed audio.
//
// MVP semantics:
//   - Each track is stored as a single file named "<sha1-of-id>.audio".
//   - A sidecar SharedPreferences key tracks last-access timestamps and
//     the total byte budget; this is enough to evict cold entries.
//   - Cache is opportunistic — tracks are only persisted after a stream
//     has been fully downloaded by the caller. For just_audio's progressive
//     HTTP playback we'd hook a `LockCachingAudioSource` here in v0.2;
//     for now this class is the data-plane only.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioCache {
  AudioCache._(this._dir, this._prefs, this._maxBytes);

  final Directory _dir;
  final SharedPreferences _prefs;
  final int _maxBytes;

  static const _kIndexKey = 'audio_cache_index_v1';

  /// Open the cache; creates the cache directory if it does not exist.
  static Future<AudioCache> open({int maxBytes = 512 * 1024 * 1024}) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/audio-cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    final prefs = await SharedPreferences.getInstance();
    return AudioCache._(dir, prefs, maxBytes);
  }

  /// Path on disk where the audio bytes for [trackId] live (whether or
  /// not the file actually exists).
  File fileFor(String trackId) {
    final hash = sha1.convert(utf8.encode(trackId)).toString();
    return File('${_dir.path}/$hash.audio');
  }

  bool hasCached(String trackId) => fileFor(trackId).existsSync();

  /// Record a hit so this entry survives the next eviction sweep.
  Future<void> touch(String trackId) async {
    final index = _index();
    index[trackId] = DateTime.now().millisecondsSinceEpoch;
    await _saveIndex(index);
  }

  /// Persist a fully-downloaded blob.
  Future<void> store(String trackId, List<int> bytes) async {
    final f = fileFor(trackId);
    await f.writeAsBytes(bytes, flush: true);
    await touch(trackId);
    await _evictIfNeeded();
  }

  Future<int> currentSizeBytes() async {
    var total = 0;
    await for (final entity in _dir.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<void> clear() async {
    await for (final entity in _dir.list()) {
      if (entity is File) await entity.delete();
    }
    await _prefs.remove(_kIndexKey);
  }

  Map<String, int> _index() {
    final raw = _prefs.getString(_kIndexKey);
    if (raw == null) return <String, int>{};
    return (jsonDecode(raw) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  Future<void> _saveIndex(Map<String, int> idx) =>
      _prefs.setString(_kIndexKey, jsonEncode(idx));

  Future<void> _evictIfNeeded() async {
    var total = await currentSizeBytes();
    if (total <= _maxBytes) return;

    final index = _index();
    // Oldest first.
    final entries = index.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    for (final e in entries) {
      if (total <= _maxBytes) break;
      final f = fileFor(e.key);
      if (await f.exists()) {
        total -= await f.length();
        await f.delete();
      }
      index.remove(e.key);
    }
    await _saveIndex(index);
  }
}
