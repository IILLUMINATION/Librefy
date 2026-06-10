package catalog

import (
	"database/sql"
	"encoding/json"

	"github.com/librefy/librefy/backend/internal/domain"
)

// scanTracks is intentionally duplicated from service.scanTracks to keep
// the providers package free of any service-internal helpers; the two
// are tiny and the duplication keeps layering clean.
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
