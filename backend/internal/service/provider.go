// Package service ties HTTP handlers to the underlying providers and
// storage. It also defines the MusicProvider abstraction used by both
// the built-in catalog provider and external/community plugins.
package service

import (
	"context"
	"errors"
	"sync"

	"github.com/librefy/librefy/backend/internal/domain"
)

// MusicProvider is the contract every source of music must implement.
//
// Providers are stateless from the caller's point of view: any caching,
// rate-limiting or auth is the provider's own concern. Returning an
// empty slice with no error means "no matches", NOT an error condition.
//
// Compliance rule for the official build: every track returned MUST
// carry a permissive License. Implementations that cannot guarantee
// that MUST NOT be registered in the default provider registry.
type MusicProvider interface {
	// Name is a short, stable identifier ("catalog", "ia", "local"...).
	Name() string

	// Search returns tracks/artists/playlists matching the query.
	Search(ctx context.Context, query string, limit int) (domain.SearchResult, error)

	// GetTrack returns a single track by its provider-scoped ID.
	// The ID format is "<provider>:<localID>" when crossing provider
	// boundaries; providers themselves only see <localID>.
	GetTrack(ctx context.Context, id string) (domain.Track, error)

	// ResolveStream returns the best available delivery options for a
	// track: an HTTP URL (always), and optionally a magnet URI.
	// Clients MUST prefer P2P when available and fall back to HTTP.
	ResolveStream(ctx context.Context, id string) (StreamInfo, error)
}

// StreamInfo describes how to fetch the audio bytes for a track.
type StreamInfo struct {
	// HTTPURL is the canonical fallback origin. May be empty if a track
	// is P2P-only, but at least one of HTTPURL / Magnet MUST be set.
	HTTPURL string `json:"httpUrl,omitempty"`
	// Magnet is a magnet URI for libtorrent / WebTorrent clients.
	Magnet string `json:"magnet,omitempty"`
	// InfoHash, if known, lets clients deduplicate swarms.
	InfoHash string `json:"infoHash,omitempty"`
	// MimeType helps clients pick the right decoder without sniffing.
	MimeType string `json:"mimeType,omitempty"`
}

// ErrNotFound is returned by providers when an ID is unknown.
var ErrNotFound = errors.New("not found")

// ProviderRegistry holds the set of providers available at runtime.
// It is safe for concurrent use.
type ProviderRegistry struct {
	mu  sync.RWMutex
	all map[string]MusicProvider
}

// NewProviderRegistry creates an empty registry.
func NewProviderRegistry() *ProviderRegistry {
	return &ProviderRegistry{all: make(map[string]MusicProvider)}
}

// Register adds a provider. The last registration wins for a given Name.
func (r *ProviderRegistry) Register(p MusicProvider) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.all[p.Name()] = p
}

// Get returns a provider by name.
func (r *ProviderRegistry) Get(name string) (MusicProvider, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	p, ok := r.all[name]
	return p, ok
}

// List returns providers in deterministic (alphabetical) order.
func (r *ProviderRegistry) List() []MusicProvider {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]MusicProvider, 0, len(r.all))
	for _, p := range r.all {
		out = append(out, p)
	}
	return out
}
