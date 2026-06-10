// Package main is built as a c-shared library (liblibrefy_torrent.so /
// liblibrefy_torrent.dylib / librefy_torrent.dll) exposing a tiny C API
// for Dart FFI. Higher-level concerns (UI, scheduling, persistence
// configuration) live in the Flutter side; this layer only owns the
// torrent.Client lifecycle, magnet → file resolution, and a local HTTP
// streaming endpoint.
//
// Contract:
//   - All exported functions are safe to call from any thread.
//   - All returned C strings are owned by Go; the caller MUST copy them
//     before the next exported call that might invalidate them.
//   - Errors are reported via lt_last_error() to keep return types
//     primitive (favours FFI ergonomics).
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"fmt"
	"sync"
	"sync/atomic"
	"unsafe"
)

// session is the single global torrent.Client + http streamer pair.
// Most apps only ever need one. We still parametrise lt_create so that
// integration tests can spin up multiple in the same process.
type session struct {
	id      int64
	mgr     *manager
	streamer *streamer

	closeOnce sync.Once
}

var (
	sessionsMu sync.RWMutex
	sessions   = make(map[int64]*session)
	nextID     int64

	lastErrorMu sync.Mutex
	lastError   string
)

func setLastError(format string, args ...any) {
	lastErrorMu.Lock()
	lastError = fmt.Sprintf(format, args...)
	lastErrorMu.Unlock()
}

// lt_last_error returns a description of the most recent failure on any
// thread. Returns NULL if no error has been recorded since the last
// successful call.
//
//export lt_last_error
func lt_last_error() *C.char {
	lastErrorMu.Lock()
	defer lastErrorMu.Unlock()
	if lastError == "" {
		return nil
	}
	return C.CString(lastError)
}

// lt_create opens a new session. cacheDir is where torrent data and the
// resume state live; it is created if it does not exist. listenPort=0
// asks the OS for a free port.
//
//export lt_create
func lt_create(cacheDir *C.char, listenPort C.int) C.int64_t {
	dir := C.GoString(cacheDir)
	mgr, err := newManager(dir, int(listenPort))
	if err != nil {
		setLastError("create: %v", err)
		return -1
	}
	str, err := newStreamer(mgr)
	if err != nil {
		mgr.Close()
		setLastError("create: streamer: %v", err)
		return -1
	}
	id := atomic.AddInt64(&nextID, 1)
	s := &session{id: id, mgr: mgr, streamer: str}
	sessionsMu.Lock()
	sessions[id] = s
	sessionsMu.Unlock()
	return C.int64_t(id)
}

// lt_destroy releases all resources owned by the session and stops the
// HTTP streamer.
//
//export lt_destroy
func lt_destroy(sid C.int64_t) {
	s := pop(int64(sid))
	if s == nil {
		return
	}
	s.closeOnce.Do(func() {
		s.streamer.Close()
		s.mgr.Close()
	})
}

// lt_add_magnet registers a magnet URI with the session and returns an
// opaque handle. The torrent starts in "metadata-only" state: pieces are
// only fetched once the caller requests a stream URL. Returns -1 on error.
//
//export lt_add_magnet
func lt_add_magnet(sid C.int64_t, magnet *C.char) C.int64_t {
	s := lookup(int64(sid))
	if s == nil {
		setLastError("add_magnet: invalid session")
		return -1
	}
	h, err := s.mgr.AddMagnet(C.GoString(magnet))
	if err != nil {
		setLastError("add_magnet: %v", err)
		return -1
	}
	return C.int64_t(h)
}

// lt_wait_metadata blocks until metadata is available for the handle or
// the timeout (in ms) elapses. Returns the number of files in the
// torrent, or -1 on timeout / error.
//
//export lt_wait_metadata
func lt_wait_metadata(sid C.int64_t, handle C.int64_t, timeoutMs C.int) C.int {
	s := lookup(int64(sid))
	if s == nil {
		setLastError("wait_metadata: invalid session")
		return -1
	}
	n, err := s.mgr.WaitMetadata(int64(handle), int(timeoutMs))
	if err != nil {
		setLastError("wait_metadata: %v", err)
		return -1
	}
	return C.int(n)
}

// lt_stream_url returns the local HTTP URL serving file [fileIdx] of
// the given handle. Caller should give it to media_kit / any HTTP audio
// player. The returned C string is allocated with C.malloc; the caller
// is responsible for freeing it.
//
//export lt_stream_url
func lt_stream_url(sid C.int64_t, handle C.int64_t, fileIdx C.int) *C.char {
	s := lookup(int64(sid))
	if s == nil {
		setLastError("stream_url: invalid session")
		return nil
	}
	url, err := s.streamer.URLFor(int64(handle), int(fileIdx))
	if err != nil {
		setLastError("stream_url: %v", err)
		return nil
	}
	return C.CString(url)
}

// lt_stats_json fills 'out' with a JSON document describing the handle:
//   {"peers":int,"downloadRate":int,"uploadRate":int,"progress":float,"bytesCompleted":int,"length":int}
// Returns the number of bytes written, or -1 on error. If the buffer is
// too small, returns the required size.
//
//export lt_stats_json
func lt_stats_json(sid C.int64_t, handle C.int64_t, out *C.char, outLen C.int) C.int {
	s := lookup(int64(sid))
	if s == nil {
		setLastError("stats: invalid session")
		return -1
	}
	js, err := s.mgr.StatsJSON(int64(handle))
	if err != nil {
		setLastError("stats: %v", err)
		return -1
	}
	b := []byte(js)
	if int(outLen) < len(b)+1 {
		return C.int(len(b) + 1)
	}
	// memcpy via unsafe — out is a raw C buffer.
	dst := unsafe.Slice((*byte)(unsafe.Pointer(out)), int(outLen))
	copy(dst, b)
	dst[len(b)] = 0
	return C.int(len(b))
}

// lt_release stops sharing/downloading the torrent. The cached data is
// kept on disk for the next session unless lt_drop_data is called.
//
//export lt_release
func lt_release(sid C.int64_t, handle C.int64_t) {
	s := lookup(int64(sid))
	if s == nil {
		return
	}
	s.mgr.Release(int64(handle))
}

// lt_free_cstring frees a C string previously returned by an exported
// function (lt_stream_url, lt_last_error). Required because Dart FFI
// cannot call C.free directly on an opaque pointer cleanly.
//
//export lt_free_cstring
func lt_free_cstring(p *C.char) {
	if p != nil {
		C.free(unsafe.Pointer(p))
	}
}

func lookup(id int64) *session {
	sessionsMu.RLock()
	defer sessionsMu.RUnlock()
	return sessions[id]
}

func pop(id int64) *session {
	sessionsMu.Lock()
	defer sessionsMu.Unlock()
	s := sessions[id]
	delete(sessions, id)
	return s
}

// The c-shared build mode requires a main function even when no
// executable is produced.
func main() {}
