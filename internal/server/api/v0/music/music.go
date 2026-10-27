// Package v0_music serves /api/v0/music: the music library built from the
// audio files on each device. Songs, albums, artists and genres, the tag
// search and the library's scan status are open to every account and list
// only what the caller can read. Each account's play history, POST
// /music/plays and GET /music/history, is its own. Queuing a rescan, POST
// /music/rescan, is admin-only. Cover art is the thumbnail route and the audio itself the file
// download (docs/architecture/music-library.md).
package v0_music

import (
	"github.com/autobutler-org/quark/pkg/util/musicutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

func NewRouter() serverutil.Router {
	return &router{}
}

// NewAdminRouter returns the route that queues a full library scan. Mount it
// behind middleware.RequireAdmin: a scan reads every device.
func NewAdminRouter() serverutil.Router {
	return &adminRouter{}
}

// TracksResponse is a page of tracks and how many the caller can see.
type TracksResponse struct {
	Tracks []musicutil.Track `json:"tracks"`
	Total  int               `json:"total"`
}

// AlbumsResponse is a page of albums and how many the caller can see.
type AlbumsResponse struct {
	Albums []musicutil.Album `json:"albums"`
	Total  int               `json:"total"`
}

// ArtistsResponse is a page of album artists and how many the caller can see.
type ArtistsResponse struct {
	Artists []musicutil.Artist `json:"artists"`
	Total   int                `json:"total"`
}

// GenresResponse is every genre the caller can see.
type GenresResponse struct {
	Genres []musicutil.Genre `json:"genres"`
}

// SearchResponse is the readable matches, best ranked first.
type SearchResponse struct {
	Results []musicutil.SearchResult `json:"results"`
}

// HistoryResponse is the caller's played tracks, in the asked order.
type HistoryResponse struct {
	Tracks []musicutil.PlayedTrack `json:"tracks"`
}
