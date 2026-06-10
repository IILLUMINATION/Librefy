// Package config loads runtime configuration from environment variables
// with sensible defaults. Keeping the surface tiny is intentional — the
// backend is meant to run locally or on a small VPS without ceremony.
package config

import (
	"os"
	"path/filepath"
)

// Config holds the runtime configuration for librefyd.
type Config struct {
	// Addr is the TCP listen address, e.g. ":8080".
	Addr string
	// DBPath is the on-disk path to the SQLite database file.
	DBPath string
	// SeedPath is the path to a JSON file that seeds the catalog
	// when the database is empty. May be empty to disable seeding.
	SeedPath string
}

// Load reads configuration from environment variables.
func Load() (*Config, error) {
	cfg := &Config{
		Addr:     getenv("LIBREFY_ADDR", ":8080"),
		DBPath:   getenv("LIBREFY_DB", defaultDBPath()),
		// Empty by default ⇒ use the seed embedded into the binary.
		// Set LIBREFY_SEED=/path/to/tracks.json to override at runtime.
		SeedPath: os.Getenv("LIBREFY_SEED"),
	}
	return cfg, nil
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func defaultDBPath() string {
	// Place the DB next to the binary by default so a single binary +
	// data file deployment is trivial.
	wd, err := os.Getwd()
	if err != nil {
		return "librefy.db"
	}
	return filepath.Join(wd, "librefy.db")
}
