package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"time"

	"github.com/anacrolix/torrent"
	"github.com/anacrolix/torrent/metainfo"
)

// manager owns a torrent.Client and tracks open torrents by handle id.
type manager struct {
	cli      *torrent.Client
	cacheDir string

	mu      sync.RWMutex
	handles map[int64]*torrent.Torrent
	nextH   int64
}

func newManager(cacheDir string, listenPort int) (*manager, error) {
	if cacheDir == "" {
		return nil, errors.New("cacheDir is required")
	}
	if err := os.MkdirAll(cacheDir, 0o755); err != nil {
		return nil, fmt.Errorf("mkdir cache: %w", err)
	}

	cfg := torrent.NewDefaultClientConfig()
	cfg.DataDir = cacheDir
	cfg.Seed = true
	cfg.NoUpload = false
	cfg.DisableIPv6 = false
	cfg.ListenPort = listenPort

	// Sensible defaults for an audio-streaming workload:
	//   - lots of small reads, low concurrency,
	//   - we want fast first-byte more than aggregate throughput.
	cfg.EstablishedConnsPerTorrent = 50
	cfg.HalfOpenConnsPerTorrent = 25

	cli, err := torrent.NewClient(cfg)
	if err != nil {
		return nil, fmt.Errorf("torrent client: %w", err)
	}
	return &manager{
		cli:      cli,
		cacheDir: cacheDir,
		handles:  make(map[int64]*torrent.Torrent),
	}, nil
}

func (m *manager) Close() error {
	m.cli.Close()
	return nil
}

// AddMagnet kicks off (or attaches to) a torrent identified by magnet.
// Returns an internal handle id; the underlying torrent is reused if a
// magnet for the same infohash has already been added.
func (m *manager) AddMagnet(magnet string) (int64, error) {
	t, err := m.cli.AddMagnet(magnet)
	if err != nil {
		return 0, err
	}
	h := atomic.AddInt64(&m.nextH, 1)
	m.mu.Lock()
	m.handles[h] = t
	m.mu.Unlock()
	return h, nil
}

// WaitMetadata blocks until the torrent's <info> section is available
// (we don't know file names / sizes before that). Returns file count.
func (m *manager) WaitMetadata(handle int64, timeoutMs int) (int, error) {
	t, ok := m.lookup(handle)
	if !ok {
		return 0, errors.New("unknown handle")
	}
	if timeoutMs <= 0 {
		timeoutMs = 60_000
	}
	select {
	case <-t.GotInfo():
	case <-time.After(time.Duration(timeoutMs) * time.Millisecond):
		return 0, fmt.Errorf("metadata timeout after %dms", timeoutMs)
	}
	return len(t.Files()), nil
}

// File returns the [idx]-th file of the torrent. Caller must have
// already received the metadata.
func (m *manager) File(handle int64, idx int) (*torrent.File, error) {
	t, ok := m.lookup(handle)
	if !ok {
		return nil, errors.New("unknown handle")
	}
	files := t.Files()
	if idx < 0 || idx >= len(files) {
		return nil, fmt.Errorf("file index %d out of range (0..%d)", idx, len(files)-1)
	}
	return files[idx], nil
}

// InfoHash returns the hex info-hash for the handle. Useful as a stable
// identifier for URL routing.
func (m *manager) InfoHash(handle int64) (string, error) {
	t, ok := m.lookup(handle)
	if !ok {
		return "", errors.New("unknown handle")
	}
	return t.InfoHash().HexString(), nil
}

// Release drops the torrent from the active set. Cached data on disk
// stays — call DropData() instead for a hard delete.
func (m *manager) Release(handle int64) {
	t, ok := m.popHandle(handle)
	if !ok {
		return
	}
	t.Drop()
}

// DropData removes the torrent and its on-disk data.
func (m *manager) DropData(handle int64) {
	t, ok := m.popHandle(handle)
	if !ok {
		return
	}
	mi := t.Metainfo()
	t.Drop()
	// Best-effort cleanup; for multi-file torrents this is the dir tree
	// containing all files. Names come from the metainfo.
	if info, err := mi.UnmarshalInfo(); err == nil {
		path := filepath.Join(m.cacheDir, info.Name)
		_ = os.RemoveAll(path)
	}
}

// StatsJSON returns a JSON snapshot of the handle's live stats.
func (m *manager) StatsJSON(handle int64) (string, error) {
	t, ok := m.lookup(handle)
	if !ok {
		return "", errors.New("unknown handle")
	}
	stats := t.Stats()
	payload := map[string]any{
		"peers":             stats.ActivePeers,
		"totalPeers":        stats.TotalPeers,
		"halfOpenPeers":     stats.HalfOpenPeers,
		"pendingPeers":      stats.PendingPeers,
		"bytesCompleted":    t.BytesCompleted(),
		"length":            t.Length(),
		"infoHash":          t.InfoHash().HexString(),
		"hasInfo":           t.Info() != nil,
	}
	if t.Info() != nil {
		payload["progress"] = float64(t.BytesCompleted()) / float64(t.Length())
		payload["name"] = t.Name()
	}
	b, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

func (m *manager) lookup(handle int64) (*torrent.Torrent, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	t, ok := m.handles[handle]
	return t, ok
}

func (m *manager) popHandle(handle int64) (*torrent.Torrent, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	t, ok := m.handles[handle]
	if ok {
		delete(m.handles, handle)
	}
	return t, ok
}

// HandleByInfoHash maps an info-hash hex string back to the first
// handle that uses it. Used by the HTTP streamer to find a torrent by
// the URL path component.
func (m *manager) HandleByInfoHash(hash string) (*torrent.Torrent, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var target metainfo.Hash
	if err := target.FromHexString(hash); err != nil {
		return nil, false
	}
	for _, t := range m.handles {
		if t.InfoHash() == target {
			return t, true
		}
	}
	return nil, false
}
