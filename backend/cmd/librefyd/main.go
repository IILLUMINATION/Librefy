// Package main is the entry point for the Librefy backend daemon.
//
// Librefy is a privacy-first, libre/free music streaming service.
// The backend is intentionally lightweight: it serves metadata, search,
// playlists and license information. It is NOT a heavy audio CDN —
// heavy audio traffic is offloaded to peer-assisted delivery (e.g. torrent)
// or to upstream HTTP origins exposed by providers.
//
// IMPORTANT: This service indexes only content with permissive licenses
// (CC0, Creative Commons, public-domain, royalty-free, artist-redistributable).
// It does NOT index or stream commercial copyrighted material.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/librefy/librefy/backend/internal/config"
	"github.com/librefy/librefy/backend/internal/db"
	httpapi "github.com/librefy/librefy/backend/internal/http"
	"github.com/librefy/librefy/backend/internal/providers/catalog"
	"github.com/librefy/librefy/backend/internal/providers/ia"
	"github.com/librefy/librefy/backend/internal/service"
)

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	cfg, err := config.Load()
	if err != nil {
		logger.Error("failed to load config", "err", err)
		os.Exit(1)
	}

	database, err := db.Open(cfg.DBPath)
	if err != nil {
		logger.Error("failed to open database", "err", err)
		os.Exit(1)
	}
	defer database.Close()

	if err := db.Migrate(database); err != nil {
		logger.Error("failed to migrate database", "err", err)
		os.Exit(1)
	}

	// Seed the catalog with permissively-licensed sample tracks if empty.
	if err := db.SeedIfEmpty(database, cfg.SeedPath); err != nil {
		logger.Warn("failed to seed database", "err", err)
	}

	// Build providers. The official build ships only with libre-safe providers.
	// External/community providers can be added via plugins later; they are
	// the responsibility of the operator who enables them.
	catalogProv := catalog.New(database)
	iaProv := ia.New(&http.Client{Timeout: 10 * time.Second})

	registry := service.NewProviderRegistry()
	registry.Register(catalogProv)
	registry.Register(iaProv)

	svc := service.New(registry, database)

	router := httpapi.NewRouter(svc, logger)

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           router,
		ReadHeaderTimeout: 10 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		logger.Info("librefyd listening", "addr", cfg.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("http server error", "err", err)
			stop()
		}
	}()

	<-ctx.Done()
	logger.Info("shutting down")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("graceful shutdown failed", "err", err)
	}
}
