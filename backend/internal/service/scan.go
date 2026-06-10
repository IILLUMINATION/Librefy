package service

import (
	"database/sql"
	"encoding/json"

	"github.com/librefy/librefy/backend/internal/domain"
)

// scanTracks is a shared helper because tracks are read from many places.
// Keeping it in one spot makes column-order bugs impossible by construction.
func scanTracks(rows *sql.Rows) ([]domain.Track, error) {
	var out []domain.Track
	for rows.Next() {
		var t domain.Track
		var album, artwork, streamURL, magnet, infoHash, licURL, attr, tagsJSON sql.NullString
		if err := rows.Scan(
			&t.ID, &t.Title, &t.Artist, &album, &t.DurationMS, &artwork,
			&streamURL, &magnet, &infoHash, &t.FileIndex,
			&t.License.Code, &t.License.Name, &licURL, &attr,
			&tagsJSON, &t.Provider, &t.AddedAt,
		); err != nil {
			return nil, err
		}
		t.Album = album.String
		t.ArtworkURL = artwork.String
		t.StreamURL = streamURL.String
		t.Magnet = magnet.String
		t.InfoHash = infoHash.String
		t.License.URL = licURL.String
		t.Attribution = attr.String
		if tagsJSON.Valid && tagsJSON.String != "" {
			_ = json.Unmarshal([]byte(tagsJSON.String), &t.Tags)
		}
		out = append(out, t)
	}
	return out, rows.Err()
}
