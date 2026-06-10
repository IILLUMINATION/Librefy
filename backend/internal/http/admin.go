// Admin HTTP surface.
//
// Mounted at /admin/v1/* and protected by a single bearer/header token
// configured via LIBREFY_ADMIN_TOKEN. If the token is empty at startup,
// the entire /admin tree is rejected with 404 — the safest default for
// a freshly-deployed binary.
package http

import (
	"crypto/subtle"
	"embed"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/librefy/librefy/backend/internal/domain"
	"github.com/librefy/librefy/backend/internal/service"
)

//go:embed adminui/*
var adminUIFS embed.FS

func mountAdmin(r chi.Router, svc *service.Service, adminToken string) {
	if adminToken == "" {
		// Explicitly refuse: don't even expose the path. A new operator
		// must opt in by setting LIBREFY_ADMIN_TOKEN before anything
		// privileged becomes reachable.
		r.Route("/admin", func(r chi.Router) {
			r.HandleFunc("/*", func(w http.ResponseWriter, _ *http.Request) {
				http.NotFound(w, nil)
			})
		})
		return
	}

	h := &adminHandlers{svc: svc}

	r.Route("/admin", func(r chi.Router) {
		// Web UI — three small static files. We serve each one explicitly
		// from the embedded FS so http.FileServer's directory-index
		// redirect quirks can't trip us up.
		serveUI := func(name, mime string) http.HandlerFunc {
			return func(w http.ResponseWriter, _ *http.Request) {
				data, err := adminUIFS.ReadFile("adminui/" + name)
				if err != nil {
					http.NotFound(w, nil)
					return
				}
				w.Header().Set("Content-Type", mime)
				w.Header().Set("Cache-Control", "no-cache")
				_, _ = w.Write(data)
			}
		}
		r.Get("/", func(w http.ResponseWriter, r *http.Request) {
			http.Redirect(w, r, "/admin/index.html", http.StatusFound)
		})
		r.Get("/index.html", serveUI("index.html", "text/html; charset=utf-8"))
		r.Get("/app.js", serveUI("app.js", "application/javascript; charset=utf-8"))
		r.Get("/styles.css", serveUI("styles.css", "text/css; charset=utf-8"))

		// Token verification endpoint — used by the UI to validate the
		// token entered by the user without leaking timing info.
		r.With(requireAdminToken(adminToken)).Get("/v1/ping", func(w http.ResponseWriter, _ *http.Request) {
			writeJSON(w, http.StatusOK, map[string]any{"ok": true})
		})

		// All mutating endpoints sit behind the token middleware.
		r.Route("/v1", func(r chi.Router) {
			r.Use(requireAdminToken(adminToken))

			r.Get("/stats", h.stats)

			r.Get("/tracks", h.listTracks)
			r.Post("/tracks", h.upsertTrack)
			r.Post("/tracks/bulk", h.bulkTracks)
			r.Delete("/tracks/{id}", h.deleteTrack)

			r.Get("/playlists", h.listPlaylists)
			r.Post("/playlists", h.upsertPlaylist)
			r.Delete("/playlists/{id}", h.deletePlaylist)

			r.Get("/seed/export", h.exportSeed)
		})
	})
}

// requireAdminToken accepts the token via:
//
//	Authorization: Bearer <token>
//	X-Admin-Token: <token>
//	?token=<token>  (only for GETs from the UI/static <script>)
func requireAdminToken(expected string) func(http.Handler) http.Handler {
	expectedB := []byte(expected)
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			got := r.Header.Get("X-Admin-Token")
			if got == "" {
				if auth := r.Header.Get("Authorization"); strings.HasPrefix(auth, "Bearer ") {
					got = strings.TrimPrefix(auth, "Bearer ")
				}
			}
			if got == "" && r.Method == http.MethodGet {
				got = r.URL.Query().Get("token")
			}
			if subtle.ConstantTimeCompare([]byte(got), expectedB) != 1 {
				w.Header().Set("WWW-Authenticate", `Bearer realm="librefy-admin"`)
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

type adminHandlers struct {
	svc *service.Service
}

func (h *adminHandlers) stats(w http.ResponseWriter, r *http.Request) {
	s, err := h.svc.AdminStats(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, s)
}

func (h *adminHandlers) listTracks(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	tracks, err := h.svc.AdminListTracks(r.Context(), limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"tracks": tracks})
}

func (h *adminHandlers) upsertTrack(w http.ResponseWriter, r *http.Request) {
	var t domain.Track
	if err := json.NewDecoder(r.Body).Decode(&t); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := h.svc.AdminUpsertTrack(r.Context(), t); err != nil {
		switch {
		case errors.Is(err, service.ErrBadInput):
			writeError(w, http.StatusBadRequest, err)
		case errors.Is(err, service.ErrConflict):
			writeError(w, http.StatusConflict, err)
		default:
			writeError(w, http.StatusInternalServerError, err)
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "id": t.ID})
}

func (h *adminHandlers) bulkTracks(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		Tracks []domain.Track `json:"tracks"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	var ok, failed int
	var errs []string
	for _, t := range payload.Tracks {
		if err := h.svc.AdminUpsertTrack(r.Context(), t); err != nil {
			failed++
			errs = append(errs, t.ID+": "+err.Error())
			continue
		}
		ok++
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":     ok,
		"failed": failed,
		"errors": errs,
	})
}

func (h *adminHandlers) deleteTrack(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if err := h.svc.AdminDeleteTrack(r.Context(), id); err != nil {
		if errors.Is(err, service.ErrNotFound) {
			writeError(w, http.StatusNotFound, err)
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *adminHandlers) listPlaylists(w http.ResponseWriter, r *http.Request) {
	pls, err := h.svc.AdminListPlaylists(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"playlists": pls})
}

func (h *adminHandlers) upsertPlaylist(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		domain.Playlist
		TrackIDs []string `json:"trackIds"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := h.svc.AdminUpsertPlaylist(r.Context(), payload.Playlist, payload.TrackIDs); err != nil {
		if errors.Is(err, service.ErrBadInput) {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "id": payload.ID})
}

func (h *adminHandlers) deletePlaylist(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if err := h.svc.AdminDeletePlaylist(r.Context(), id); err != nil {
		if errors.Is(err, service.ErrNotFound) {
			writeError(w, http.StatusNotFound, err)
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *adminHandlers) exportSeed(w http.ResponseWriter, r *http.Request) {
	raw, err := h.svc.AdminExportSeed(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="tracks.json"`)
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(raw)
}
