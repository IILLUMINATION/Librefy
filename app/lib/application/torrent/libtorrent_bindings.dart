// Hand-written FFI bindings for liblibrefy_torrent.so / .dylib / .dll.
//
// Why hand-written and not ffigen-generated:
//   - Our C surface is tiny (8 functions) — codegen is overkill.
//   - Keeps the build pipeline simple: no need to ship a libclang on
//     every developer machine.
//
// Memory ownership rules (must hold):
//   - C strings returned by lt_stream_url / lt_last_error are OWNED by
//     the native lib. We free them by calling lt_free_cstring.
//   - C strings PASSED IN are copied by Go; we may free them
//     immediately after the call.
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

// ----------------------------------------------------------------------
//  Native function signatures
// ----------------------------------------------------------------------

typedef _CreateNative = ffi.Int64 Function(
    ffi.Pointer<Utf8> cacheDir, ffi.Int32 listenPort);
typedef _Create = int Function(ffi.Pointer<Utf8> cacheDir, int listenPort);

typedef _DestroyNative = ffi.Void Function(ffi.Int64 sid);
typedef _Destroy = void Function(int sid);

typedef _AddMagnetNative = ffi.Int64 Function(
    ffi.Int64 sid, ffi.Pointer<Utf8> magnet);
typedef _AddMagnet = int Function(int sid, ffi.Pointer<Utf8> magnet);

typedef _WaitMetadataNative = ffi.Int32 Function(
    ffi.Int64 sid, ffi.Int64 handle, ffi.Int32 timeoutMs);
typedef _WaitMetadata = int Function(int sid, int handle, int timeoutMs);

typedef _StreamUrlNative = ffi.Pointer<Utf8> Function(
    ffi.Int64 sid, ffi.Int64 handle, ffi.Int32 fileIdx);
typedef _StreamUrl = ffi.Pointer<Utf8> Function(
    int sid, int handle, int fileIdx);

typedef _StatsJsonNative = ffi.Int32 Function(
    ffi.Int64 sid, ffi.Int64 handle, ffi.Pointer<ffi.Char> out, ffi.Int32 len);
typedef _StatsJson = int Function(
    int sid, int handle, ffi.Pointer<ffi.Char> out, int len);

typedef _ReleaseNative = ffi.Void Function(ffi.Int64 sid, ffi.Int64 handle);
typedef _Release = void Function(int sid, int handle);

typedef _LastErrorNative = ffi.Pointer<Utf8> Function();
typedef _LastError = ffi.Pointer<Utf8> Function();

typedef _FreeCStringNative = ffi.Void Function(ffi.Pointer<Utf8> p);
typedef _FreeCString = void Function(ffi.Pointer<Utf8> p);

// ----------------------------------------------------------------------
//  Bindings
// ----------------------------------------------------------------------

class LibtorrentBindings {
  LibtorrentBindings._(ffi.DynamicLibrary lib)
      : ltCreate = lib.lookupFunction<_CreateNative, _Create>('lt_create'),
        ltDestroy = lib.lookupFunction<_DestroyNative, _Destroy>('lt_destroy'),
        ltAddMagnet =
            lib.lookupFunction<_AddMagnetNative, _AddMagnet>('lt_add_magnet'),
        ltWaitMetadata =
            lib.lookupFunction<_WaitMetadataNative, _WaitMetadata>('lt_wait_metadata'),
        ltStreamUrl =
            lib.lookupFunction<_StreamUrlNative, _StreamUrl>('lt_stream_url'),
        ltStatsJson =
            lib.lookupFunction<_StatsJsonNative, _StatsJson>('lt_stats_json'),
        ltRelease = lib.lookupFunction<_ReleaseNative, _Release>('lt_release'),
        ltLastError =
            lib.lookupFunction<_LastErrorNative, _LastError>('lt_last_error'),
        ltFreeCString =
            lib.lookupFunction<_FreeCStringNative, _FreeCString>('lt_free_cstring');

  final _Create ltCreate;
  final _Destroy ltDestroy;
  final _AddMagnet ltAddMagnet;
  final _WaitMetadata ltWaitMetadata;
  final ffi.Pointer<Utf8> Function(int, int, int) ltStreamUrl;
  final _StatsJson ltStatsJson;
  final _Release ltRelease;
  final ffi.Pointer<Utf8> Function() ltLastError;
  final _FreeCString ltFreeCString;

  /// Open the native library shipped with the app.
  ///
  /// Lookup strategy:
  ///   - Android  →  System loader: `liblibrefy_torrent.so` (in jniLibs).
  ///   - Linux    →  `lib/liblibrefy_torrent.so` next to the executable
  ///                  (RPATH `$ORIGIN/lib` on the runner picks it up).
  ///   - macOS    →  `liblibrefy_torrent.dylib`.
  ///   - Windows  →  `librefy_torrent.dll`.
  static LibtorrentBindings? tryOpen() {
    try {
      final lib = _openPlatform();
      return LibtorrentBindings._(lib);
    } on ArgumentError {
      return null;
    } catch (_) {
      return null;
    }
  }

  static ffi.DynamicLibrary _openPlatform() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('liblibrefy_torrent.so');
    }
    if (Platform.isLinux) {
      return ffi.DynamicLibrary.open('liblibrefy_torrent.so');
    }
    if (Platform.isMacOS) {
      return ffi.DynamicLibrary.open('liblibrefy_torrent.dylib');
    }
    if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('librefy_torrent.dll');
    }
    throw UnsupportedError('libtorrent bridge unavailable on this platform');
  }

  /// Reads (and consumes) the most recent error from the native side.
  String? lastError() {
    final p = ltLastError();
    if (p.address == 0) return null;
    final msg = p.toDartString();
    ltFreeCString(p);
    return msg;
  }
}
