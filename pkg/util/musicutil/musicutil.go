// Package musicutil keeps the music library: the music_tracks cache built
// from the audio files on each device, the Songs, Albums, Artists and Genres
// views over it, and the tag search (#2982, docs/architecture/music-library.md).
//
// Every row is derived from a file, so the table is a cache a rescan
// rebuilds. IndexTrack reads one file's tags through audiotagutil and upserts
// its row; BackfillDevice walks a device and re-reads only the files whose
// size, mtime or ScannerVersion changed, then drops the rows of files it did
// not see. DeletePath, MovePath and DropDevice keep the rows in step with the
// tree without reading anything. Files are reached only through pkg/vfs.
//
// The browse functions filter by access. An admin's page is one SQL
// aggregate; anyone else's streams the rows in batches through
// accessutil.Check and aggregates in Go, so a listing, a count, a cover or a
// search hit never names a file the caller cannot read.
//
// Search is FTS5 and so SQLite only: on PostgreSQL it answers a
// *db.UnsupportedError until #2958.
package musicutil

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// ScannerVersion is stored on every row. Raise it when tag reading improves:
// a backfill re-reads every row stored under an older version.
const ScannerVersion = 1

// FileTimeout bounds the work on one file during a backfill.
const FileTimeout = 5 * time.Second

// DefaultLimit is the page a listing or search returns when the caller names
// none.
const DefaultLimit = 50

// MaxLimit is the largest page a listing or search returns.
const MaxLimit = 200

// ErrInvalidSort is returned for a TrackSort that is not one of the named
// ones.
var ErrInvalidSort = errors.New("musicutil: unknown track sort")

// IsAudioPath reports whether a path names a file the library indexes, by its
// extension: mp3, aac, flac, ogg, opus, m4a, wav and wma.
func IsAudioPath(p string) bool {
	return isAudioPath(p)
}

// Track is one song in the library.
type Track struct {
	// Serial is the device holding the file, '' for the internal drive.
	Serial string `json:"serial"`
	// RelPath is the file's path within the device's files namespace.
	RelPath string `json:"relPath"`
	// Title is the tagged title, or the file name without its extension.
	Title string `json:"title"`
	// Artist is the track artist.
	Artist string `json:"artist"`
	// AlbumArtist is the album artist, the track artist when untagged.
	AlbumArtist string `json:"albumArtist"`
	// Album is the album title.
	Album string `json:"album"`
	// AlbumKey identifies the album: album artist, album, device and folder.
	AlbumKey string `json:"albumKey"`
	// Genre is the genre.
	Genre string `json:"genre"`
	// TrackNo is the track number, 0 when untagged.
	TrackNo int `json:"trackNo"`
	// DiscNo is the disc number, 0 when untagged.
	DiscNo int `json:"discNo"`
	// Year is the release year, 0 when untagged.
	Year int `json:"year"`
	// DurationMs is the playing time, 0 when unknown.
	DurationMs int64 `json:"durationMs"`
	// DurationExact is false when DurationMs is a bitrate estimate.
	DurationExact bool `json:"durationExact"`
	// HasCover reports embedded or folder cover art.
	HasCover bool `json:"hasCover"`
}

// Album is a group of tracks sharing an AlbumKey.
type Album struct {
	AlbumKey    string `json:"albumKey"`
	Title       string `json:"title"`
	AlbumArtist string `json:"albumArtist"`
	// Year is the earliest tagged year among the tracks, 0 when none is.
	Year       int   `json:"year"`
	TrackCount int   `json:"trackCount"`
	DurationMs int64 `json:"durationMs"`
	// CoverSerial and CoverPath name the track to ask the thumbnail endpoint
	// for: one with cover art when any has it, otherwise the first.
	CoverSerial string `json:"coverSerial"`
	CoverPath   string `json:"coverPath"`
}

// Artist is an album artist and what the caller can see of their tracks.
type Artist struct {
	Name        string `json:"name"`
	AlbumCount  int    `json:"albumCount"`
	TrackCount  int    `json:"trackCount"`
	CoverSerial string `json:"coverSerial"`
	CoverPath   string `json:"coverPath"`
}

// Genre is a genre and how many visible tracks carry it.
type Genre struct {
	Name       string `json:"name"`
	TrackCount int    `json:"trackCount"`
}

// IndexTrackParams names one file to read into the library.
type IndexTrackParams struct {
	Ctx context.Context
	DB  *sql.DB
	// FS is the device's files namespace.
	FS vfs.VFS
	// Serial is the device's serial, '' for the internal drive.
	Serial  string
	RelPath string
}

// IndexTrackResult says what IndexTrack did.
type IndexTrackResult struct {
	// Indexed is true when a row was written. A path that is not audio, or
	// lies in the trash or an internal folder, writes none.
	Indexed bool
	// TagsUnreadable is true when the tags were malformed or too large. The
	// row is still written, titled from the file name, so the file stays
	// playable from the library.
	TagsUnreadable bool
}

// IndexTrack reads the file's tags and upserts its row. It always reads: an
// upload event says the file changed, whatever its size and mtime say.
func IndexTrack(params IndexTrackParams) (IndexTrackResult, error) {
	return indexTrack(params)
}

// BackfillDeviceParams names the device to scan.
type BackfillDeviceParams struct {
	Ctx context.Context
	DB  *sql.DB
	// FS is the device's files namespace.
	FS     vfs.VFS
	Serial string
	// Progress, when set, is called after every audio file with the counts
	// so far.
	Progress func(BackfillDeviceResult)
}

// BackfillDeviceResult counts what a pass did.
type BackfillDeviceResult struct {
	// Scanned is the audio files the walk visited.
	Scanned int
	// Indexed is the files read and written.
	Indexed int
	// Unchanged is the files skipped because their row still matched.
	Unchanged int
	// Unreadable is the indexed files whose tags could not be read.
	Unreadable int
	// Failed is the files that could not be read at all.
	Failed int
	// Deleted is the rows dropped because the walk did not see their file.
	Deleted int
}

// BackfillDevice brings a device's rows in step with its files. A file whose
// size, mtime and ScannerVersion match its row is not opened. Rows the walk
// did not see are deleted at the end, but only after a walk that finished: a
// canceled pass, or a device that is not mounted, deletes nothing.
func BackfillDevice(params BackfillDeviceParams) (BackfillDeviceResult, error) {
	return backfillDevice(params)
}

// DeletePathParams names a deleted file or folder.
type DeletePathParams struct {
	Ctx     context.Context
	DB      *sql.DB
	Serial  string
	RelPath string
}

// DeletePathResult is empty; DeletePath reports only failure.
type DeletePathResult struct{}

// DeletePath drops the track at RelPath and every track under it, since a
// folder delete names only the folder.
func DeletePath(params DeletePathParams) (DeletePathResult, error) {
	return DeletePathResult{}, deletePath(params)
}

// MovePathParams names a move within one device.
type MovePathParams struct {
	Ctx     context.Context
	DB      *sql.DB
	Serial  string
	OldPath string
	NewPath string
}

// MovePathResult counts the rows that moved.
type MovePathResult struct {
	Moved int
}

// MovePath rewrites the path of the track at OldPath and of every track under
// it, and recomputes their album keys, without reading a file. Rows already
// at the destination are replaced. A move between devices is a DeletePath
// on one and an IndexTrack on the other; a rename that changes whether the
// name is audio is the caller's to follow with IndexTrack or DeletePath.
func MovePath(params MovePathParams) (MovePathResult, error) {
	return movePath(params)
}

// DropDeviceParams names a device that went away.
type DropDeviceParams struct {
	Ctx    context.Context
	DB     *sql.DB
	Serial string
}

// DropDeviceResult is empty; DropDevice reports only failure.
type DropDeviceResult struct{}

// DropDevice deletes every row of a device.
func DropDevice(params DropDeviceParams) (DropDeviceResult, error) {
	return DropDeviceResult{}, dropDevice(params)
}

// TrackSort orders a track listing.
type TrackSort string

// The track sorts. The zero value is album order: album artist, album, disc,
// track. Every sort falls back to album order for ties.
const (
	SortAlbumOrder TrackSort = ""
	SortTitle      TrackSort = "title"
	SortArtist     TrackSort = "artist"
	SortAlbum      TrackSort = "album"
	SortYear       TrackSort = "year"
	SortAdded      TrackSort = "added"
)

// ListTracksParams is a page of tracks for one caller.
type ListTracksParams struct {
	Ctx    context.Context
	DB     *sql.DB
	Access accessutil.Access
	// AlbumKey keeps one album's tracks when set.
	AlbumKey string
	// Artist keeps one album artist's tracks when set, compared without
	// case. It may point at "", the untagged artist.
	Artist *string
	// Genre keeps one genre's tracks when set, compared without case.
	Genre      *string
	Sort       TrackSort
	Descending bool
	Offset     int
	// Limit is DefaultLimit when zero or less and at most MaxLimit.
	Limit int
}

// ListTracksResult is a page and the number of tracks the caller can see.
type ListTracksResult struct {
	Tracks []Track
	Total  int
}

// ListTracks returns a sorted page of the tracks the caller can read.
func ListTracks(params ListTracksParams) (ListTracksResult, error) {
	return listTracks(params)
}

// ListAlbumsParams is a page of albums for one caller.
type ListAlbumsParams struct {
	Ctx    context.Context
	DB     *sql.DB
	Access accessutil.Access
	// Artist keeps one album artist's albums, and only their tracks in the
	// counts, when set.
	Artist *string
	Offset int
	// Limit is DefaultLimit when zero or less and at most MaxLimit.
	Limit int
}

// ListAlbumsResult is a page and the number of albums the caller can see.
type ListAlbumsResult struct {
	Albums []Album
	Total  int
}

// ListAlbums returns albums ordered by album artist and title. A non-admin
// sees an album only when they can read one of its tracks, and its counts,
// year and cover come from those tracks alone.
func ListAlbums(params ListAlbumsParams) (ListAlbumsResult, error) {
	return listAlbums(params)
}

// ListArtistsParams is a page of album artists for one caller.
type ListArtistsParams struct {
	Ctx    context.Context
	DB     *sql.DB
	Access accessutil.Access
	Offset int
	// Limit is DefaultLimit when zero or less and at most MaxLimit.
	Limit int
}

// ListArtistsResult is a page and the number of artists the caller can see.
type ListArtistsResult struct {
	Artists []Artist
	Total   int
}

// ListArtists returns album artists by name, counted over the tracks the
// caller can read.
func ListArtists(params ListArtistsParams) (ListArtistsResult, error) {
	return listArtists(params)
}

// ListGenresParams lists the genres for one caller.
type ListGenresParams struct {
	Ctx    context.Context
	DB     *sql.DB
	Access accessutil.Access
}

// ListGenresResult is every genre the caller can see.
type ListGenresResult struct {
	Genres []Genre
}

// ListGenres returns genres by name, counted over the tracks the caller can
// read.
func ListGenres(params ListGenresParams) (ListGenresResult, error) {
	return listGenres(params)
}

// SearchParams is a tag search for one caller.
type SearchParams struct {
	Ctx    context.Context
	DB     *sql.DB
	Access accessutil.Access
	// Query is the user's text. Plain words are one phrase; FTS5 syntax such
	// as artist:nina passes through (searchutil.SanitizeQuery).
	Query string
	// Limit is DefaultLimit when zero or less and at most MaxLimit.
	Limit int
}

// SearchResult is one matching track.
type SearchResult struct {
	Track Track `json:"track"`
	// Snippet is the best-matching tag with the matched terms in <b>…</b>.
	// It is tag text from a file: escape it before rendering as HTML.
	Snippet string `json:"snippet"`
}

// SearchResultPage is up to Limit readable matches, best ranked first.
type SearchResultPage struct {
	Results []SearchResult
}

// Search matches the query against title, artist, album artist, album and
// genre, ranked by bm25. On PostgreSQL it returns a *db.UnsupportedError.
func Search(params SearchParams) (SearchResultPage, error) {
	return search(params)
}
