// Package http wires HTTP handlers to the application service.
//
// API surface (v1, JSON):
//
//	GET  /api/v1/health
//	GET  /api/v1/featured?limit=10
//	GET  /api/v1/trending?limit=20
//	GET  /api/v1/search?q=...&limit=20
//	GET  /api/v1/tracks/{id}          (id is "<provider>:<localID>")
//	GET  /api/v1/tracks/{id}/stream   resolves to HTTP+magnet info
//	POST /api/v1/tracks/{id}/play     anonymous play counter
//	GET  /api/v1/playlists/{id}
//
// All responses are JSON with snake-free camelCase keys to match the
// Flutter client's expectations.
package http

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"

	"github.com/librefy/librefy/backend/internal/service"
)

// NewRouter builds the full chi router for the API.
// adminToken protects the /admin/* surface; pass "" to fully disable it.
func NewRouter(svc *service.Service, logger *slog.Logger, adminToken string) http.Handler {
	r := chi.NewRouter()

	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(15 * time.Second))
	// CORS is wide-open on purpose: this is a libre catalog. Tighten it
	// behind a reverse proxy if you self-host with stricter requirements.
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins: []string{"*"},
		AllowedMethods: []string{"GET", "POST", "DELETE", "OPTIONS"},
		AllowedHeaders: []string{"Accept", "Content-Type", "Authorization", "X-Admin-Token"},
		MaxAge:         300,
	}))

	h := &handlers{svc: svc, log: logger}

	r.Route("/api/v1", func(r chi.Router) {
		r.Get("/health", h.health)
		r.Get("/featured", h.featured)
		r.Get("/trending", h.trending)
		r.Get("/search", h.search)
		r.Get("/tracks/{id}", h.getTrack)
		r.Get("/tracks/{id}/stream", h.resolveStream)
		r.Post("/tracks/{id}/play", h.recordPlay)
		r.Get("/playlists/{id}", h.getPlaylist)
	})

	mountAdmin(r, svc, adminToken)

	return r
}

type handlers struct {
	svc *service.Service
	log *slog.Logger
}

func (h *handlers) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status":  "ok",
		"service": "librefyd",
		"version": "0.1.0",
	})
}

func (h *handlers) featured(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	pls, err := h.svc.Featured(r.Context(), limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"playlists": pls})
}

func (h *handlers) trending(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	tracks, err := h.svc.Trending(r.Context(), limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"tracks": tracks})
}

func (h *handlers) search(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query().Get("q")
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	res, err := h.svc.Search(r.Context(), q, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (h *handlers) getTrack(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	t, err := h.svc.GetTrack(r.Context(), id)
	if err != nil {
		if errors.Is(err, service.ErrNotFound) {
			writeError(w, http.StatusNotFound, err)
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, t)
}

func (h *handlers) resolveStream(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	info, err := h.svc.ResolveStream(r.Context(), id)
	if err != nil {
		if errors.Is(err, service.ErrNotFound) {
			writeError(w, http.StatusNotFound, err)
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, info)
}

func (h *handlers) recordPlay(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	// Best-effort; never fail the client.
	if err := h.svc.RecordPlay(r.Context(), id); err != nil {
		h.log.Warn("record play failed", "id", id, "err", err)
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *handlers) getPlaylist(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	pl, tracks, err := h.svc.PlaylistTracks(r.Context(), id)
	if err != nil {
		if errors.Is(err, service.ErrNotFound) {
			writeError(w, http.StatusNotFound, err)
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"playlist": pl,
		"tracks":   tracks,
	})
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, map[string]any{
		"error": err.Error(),
	})
}
