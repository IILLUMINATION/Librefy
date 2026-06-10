package main

import (
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/anacrolix/torrent"
)

// streamer exposes the active torrents on a local-only HTTP server.
// media_kit (and any HTTP-aware audio player) consumes the URLs we
// produce as if they were a regular CDN — Range requests included.
type streamer struct {
	mgr  *manager
	srv  *http.Server
	port int
}

func newStreamer(mgr *manager) (*streamer, error) {
	// 127.0.0.1 only: we don't want random LAN hosts grabbing the bytes.
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, fmt.Errorf("listen loopback: %w", err)
	}
	port := ln.Addr().(*net.TCPAddr).Port

	s := &streamer{mgr: mgr, port: port}
	s.srv = &http.Server{
		Handler:           http.HandlerFunc(s.handle),
		ReadHeaderTimeout: 10 * time.Second,
	}
	go func() {
		_ = s.srv.Serve(ln)
	}()
	return s, nil
}

func (s *streamer) Close() error {
	return s.srv.Close()
}

// URLFor returns the loopback URL serving the file at fileIdx of the
// torrent identified by handle. The caller is expected to call this
// AFTER lt_wait_metadata, otherwise file count is unknown.
//
// If [fileIdx] points at a non-audio file (cover.jpg, log.txt, …) we
// remap it to the nearest audio file in the torrent. This makes the
// admin UX forgiving: file_index=0 still Just Works on releases that
// store an album cover as file 0.
func (s *streamer) URLFor(handle int64, fileIdx int) (string, error) {
	t, ok := s.mgr.lookup(handle)
	if !ok {
		return "", errors.New("unknown handle")
	}
	if t.Info() == nil {
		return "", errors.New("metadata not ready")
	}
	files := t.Files()
	if fileIdx < 0 || fileIdx >= len(files) {
		return "", fmt.Errorf("file index %d out of range", fileIdx)
	}
	if !isAudioFile(files[fileIdx].Path()) {
		// Search forwards from the requested index, wrap around once.
		remapped := -1
		for off := 1; off <= len(files); off++ {
			j := (fileIdx + off) % len(files)
			if isAudioFile(files[j].Path()) {
				remapped = j
				break
			}
		}
		if remapped < 0 {
			return "", errors.New("torrent contains no audio files")
		}
		fileIdx = remapped
	}
	// Use the info-hash as the route key — it's the only stable id that
	// the manager can resolve back to a torrent (handles are per-process).
	return fmt.Sprintf("http://127.0.0.1:%d/%s/%d",
		s.port, t.InfoHash().HexString(), fileIdx), nil
}

func isAudioFile(path string) bool {
	ext := strings.ToLower(filepath.Ext(path))
	switch ext {
	case ".mp3", ".m4a", ".mp4", ".flac", ".ogg", ".opus", ".wav",
		".aac", ".ape", ".wv", ".aif", ".aiff":
		return true
	}
	return false
}

// HTTP request path:  /<info_hash_hex>/<file_idx>
func (s *streamer) handle(w http.ResponseWriter, r *http.Request) {
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(parts) != 2 {
		http.NotFound(w, r)
		return
	}
	hash := parts[0]
	idx, err := strconv.Atoi(parts[1])
	if err != nil {
		http.Error(w, "bad file index", http.StatusBadRequest)
		return
	}
	t, ok := s.mgr.HandleByInfoHash(hash)
	if !ok || t.Info() == nil {
		http.NotFound(w, r)
		return
	}
	files := t.Files()
	if idx < 0 || idx >= len(files) {
		http.Error(w, "bad file index", http.StatusBadRequest)
		return
	}
	// Audio-file guard, same as URLFor: a saved URL might point at a
	// jpeg / nfo after an upstream metadata change.
	if !isAudioFile(files[idx].Path()) {
		remapped := -1
		for off := 1; off <= len(files); off++ {
			j := (idx + off) % len(files)
			if isAudioFile(files[j].Path()) {
				remapped = j
				break
			}
		}
		if remapped < 0 {
			http.Error(w, "no audio file in torrent", http.StatusNotFound)
			return
		}
		idx = remapped
	}
	f := files[idx]
	// Prioritise the file we're about to serve — other files in the
	// torrent are demoted so peers focus bandwidth on the playing one.
	for i, other := range files {
		if i == idx {
			other.SetPriority(torrent.PiecePriorityNow)
		} else {
			other.SetPriority(torrent.PiecePriorityNone)
		}
	}

	reader := f.NewReader()
	defer reader.Close()
	reader.SetReadahead(8 * 1024 * 1024) // 8 MiB lookahead absorbs media_kit's bursts
	reader.SetResponsive()

	w.Header().Set("Content-Type", guessMime(f.Path()))
	w.Header().Set("Accept-Ranges", "bytes")
	http.ServeContent(w, r, filepath.Base(f.Path()), time.Now(),
		&fileReadSeeker{r: reader, size: f.Length()})
}

// fileReadSeeker adapts torrent.Reader (io.ReadSeekCloser) into the
// shape http.ServeContent needs: Read + Seek with a known size. We
// don't expose ReadAt because anacrolix's Reader is positional only.
type fileReadSeeker struct {
	r    io.ReadSeekCloser
	size int64
}

func (f *fileReadSeeker) Read(p []byte) (int, error)               { return f.r.Read(p) }
func (f *fileReadSeeker) Seek(off int64, whence int) (int64, error) { return f.r.Seek(off, whence) }

func guessMime(name string) string {
	switch strings.ToLower(filepath.Ext(name)) {
	case ".mp3":
		return "audio/mpeg"
	case ".m4a", ".mp4":
		return "audio/mp4"
	case ".flac":
		return "audio/flac"
	case ".ogg":
		return "audio/ogg"
	case ".opus":
		return "audio/opus"
	case ".wav":
		return "audio/wav"
	}
	return "application/octet-stream"
}
