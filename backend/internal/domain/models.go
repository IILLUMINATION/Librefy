// Package domain defines the core entities used across the backend.
//
// These types are transport-agnostic and storage-agnostic: HTTP handlers
// map them to JSON, repositories map them to SQL rows, providers translate
// them to/from external systems.
package domain

import "time"

// License describes the legal status of a track. Librefy only indexes
// content with permissive licenses. The free-form Name plus a canonical
// SPDX-like Code lets clients display attribution correctly.
type License struct {
	// Code is a short identifier, e.g. "CC0", "CC-BY-4.0", "PD".
	Code string `json:"code"`
	// Name is a human-readable license name.
	Name string `json:"name"`
	// URL points to the canonical license text.
	URL string `json:"url,omitempty"`
}

// Track is a single playable item. Audio bytes are NEVER served by the
// backend directly — clients fetch the actual stream via StreamURL
// (HTTP fallback) or Magnet (P2P) depending on what is available.
type Track struct {
	ID         string    `json:"id"`
	Title      string    `json:"title"`
	Artist     string    `json:"artist"`
	Album      string    `json:"album,omitempty"`
	DurationMS int64     `json:"durationMs"`
	ArtworkURL string    `json:"artworkUrl,omitempty"`
	// StreamURL is the HTTP fallback origin (must be public and re-distributable).
	StreamURL string `json:"streamUrl,omitempty"`
	// Magnet is a magnet URI for peer-assisted delivery. Empty if not available.
	Magnet string `json:"magnet,omitempty"`
	// InfoHash is the torrent info-hash (hex), if known.
	InfoHash string `json:"infoHash,omitempty"`
	// FileIndex is the zero-based audio-file index inside the torrent.
	// Lets one magnet back many tracks (compilations, albums). For a
	// single-file torrent this is just 0.
	FileIndex int     `json:"fileIndex"`
	License   License `json:"license"`
	// Attribution is the required credit string per CC-BY style licenses.
	Attribution string    `json:"attribution,omitempty"`
	Tags        []string  `json:"tags,omitempty"`
	Provider    string    `json:"provider"`
	AddedAt     time.Time `json:"addedAt"`
}

// Playlist is a named, ordered collection of tracks.
type Playlist struct {
	ID          string    `json:"id"`
	Title       string    `json:"title"`
	Description string    `json:"description,omitempty"`
	ArtworkURL  string    `json:"artworkUrl,omitempty"`
	Curated     bool      `json:"curated"`
	TrackIDs    []string  `json:"trackIds"`
	UpdatedAt   time.Time `json:"updatedAt"`
}

// Artist is a (light) view of a creator. Kept small on purpose; richer
// data can be added later without breaking the schema.
type Artist struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Bio  string `json:"bio,omitempty"`
}

// SearchResult is the union returned by search endpoints.
type SearchResult struct {
	Tracks    []Track    `json:"tracks"`
	Artists   []Artist   `json:"artists"`
	Playlists []Playlist `json:"playlists"`
}
