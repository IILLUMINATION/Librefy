// On-demand "save this track to my device" feature.
//
// Two source modes:
//   - HTTP: stream the audio with dio and write it to a file, emitting
//     incremental progress.
//   - P2P / loopback torrent stream: media_kit is already pulling bytes
//     from 127.0.0.1; we just GET that same URL and dump it to disk.
//     The local server is the canonical source either way.
//
// Files land in the user's "Music/Librefy" directory when we can resolve
// one, else in the app support dir. We never overwrite without checking
// for an existing file first.
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/track.dart';

class DownloadProgress {
  const DownloadProgress({
    required this.trackId,
    required this.received,
    required this.total,
    this.path,
    this.error,
    this.done = false,
  });

  final String trackId;
  final int received;
  final int total;
  final String? path;
  final Object? error;
  final bool done;

  double get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
}

class DownloadService {
  DownloadService({Dio? dio}) : _dio = dio ?? Dio();
  final Dio _dio;

  final _progress = StreamController<DownloadProgress>.broadcast();
  Stream<DownloadProgress> get progress => _progress.stream;

  final Map<String, CancelToken> _inflight = {};

  /// Returns the absolute path of the saved file on success.
  Future<String> download(Track track, Uri sourceUri) async {
    if (_inflight.containsKey(track.id)) {
      throw StateError('Already downloading ${track.id}');
    }
    final fileName = _safeFileName(track);
    final dest = await _resolveDestination(fileName);

    final f = File(dest);
    if (await f.exists()) {
      // Don't redownload; surface the path as-is.
      _emit(DownloadProgress(
        trackId: track.id,
        received: await f.length(),
        total: await f.length(),
        path: dest,
        done: true,
      ));
      return dest;
    }

    final cancel = CancelToken();
    _inflight[track.id] = cancel;
    try {
      await _dio.download(
        sourceUri.toString(),
        dest,
        cancelToken: cancel,
        options: Options(
          // Some servers refuse mp3 fetches without a UA; mimic browser.
          headers: {'User-Agent': 'Librefy/0.1 (download)'},
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 10),
        ),
        onReceiveProgress: (rec, total) {
          _emit(DownloadProgress(
            trackId: track.id,
            received: rec,
            total: total,
          ));
        },
      );
      final len = await File(dest).length();
      _emit(DownloadProgress(
        trackId: track.id,
        received: len,
        total: len,
        path: dest,
        done: true,
      ));
      return dest;
    } catch (e) {
      // Clean up partial file.
      try {
        if (await File(dest).exists()) await File(dest).delete();
      } catch (_) {}
      _emit(DownloadProgress(
        trackId: track.id,
        received: 0,
        total: 0,
        error: e,
        done: true,
      ));
      rethrow;
    } finally {
      _inflight.remove(track.id);
    }
  }

  Future<void> cancel(String trackId) async {
    _inflight[trackId]?.cancel('user cancelled');
  }

  Future<void> dispose() async {
    for (final c in _inflight.values) {
      c.cancel('service dispose');
    }
    await _progress.close();
  }

  void _emit(DownloadProgress p) {
    if (!_progress.isClosed) _progress.add(p);
  }

  static Future<String> _resolveDestination(String fileName) async {
    // Prefer ~/Music/Librefy on Linux desktop. Fall back to the app's
    // private support directory (Android, sandboxed environments).
    Directory? base;
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'];
      if (home != null) {
        final candidate = Directory('$home/Music/Librefy');
        try {
          await candidate.create(recursive: true);
          base = candidate;
        } catch (_) {/* fall through */}
      }
    }
    base ??= Directory('${(await getApplicationSupportDirectory()).path}/downloads');
    await base.create(recursive: true);
    return '${base.path}/$fileName';
  }

  static String _safeFileName(Track track) {
    final raw = '${track.artist} - ${track.title}';
    final cleaned =
        raw.replaceAll(RegExp(r'[\/\\\:\*\?"<>\|\r\n\t]+'), '_').trim();
    final extGuess = _extFromHints(track);
    return '$cleaned$extGuess';
  }

  static String _extFromHints(Track track) {
    // Use the upstream URL extension when available, else default to .mp3.
    final url = track.streamUrl ?? '';
    final m = RegExp(r'\.(mp3|m4a|flac|ogg|opus|wav)(?:\?|$)',
            caseSensitive: false)
        .firstMatch(url);
    return m != null ? '.${m.group(1)!.toLowerCase()}' : '.mp3';
  }
}

// Provider — single instance per app. Disposes on ProviderScope teardown.
final downloadServiceProvider = Provider<DownloadService>((ref) {
  final svc = DownloadService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Per-track most recent progress event. Filters the broadcast stream
/// so each download tile only rebuilds for its own track.
final downloadProgressProvider =
    StreamProvider.family<DownloadProgress?, String>((ref, trackId) async* {
  final svc = ref.watch(downloadServiceProvider);
  yield null;
  await for (final p in svc.progress.where((p) => p.trackId == trackId)) {
    yield p;
  }
});
