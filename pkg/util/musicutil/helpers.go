package musicutil

import (
	"cmp"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"io"
	"path"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/audiotagutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// coverBaseNames are the folder images taken as cover art, in preference
// order, matched without case.
var coverBaseNames = []string{"cover", "folder", "front", "album"}

// coverExtensions are the image types a folder cover may have, in preference
// order.
var coverExtensions = []string{".jpg", ".jpeg", ".png"}

func isAudioPath(p string) bool {
	return storageutil.AudioMIMETypeFromExtension(path.Ext(p)) != "application/octet-stream"
}

// indexable reports whether a path is audio outside the trash, the version
// stores and in-flight writes.
func indexable(relPath string) bool {
	if !isAudioPath(relPath) || storageutil.IsTrashPath(relPath) {
		return false
	}
	for _, part := range strings.Split(relPath, "/") {
		if storageutil.IsInternalName(part) {
			return false
		}
	}
	return true
}

// folderOf is a path's parent, "" for the device root.
func folderOf(relPath string) string {
	dir := path.Dir(relPath)
	if dir == "." || dir == "/" {
		return ""
	}
	return dir
}

// albumKey identifies an album: album artist and album without case, plus
// the device and folder holding the track, so two "Greatest Hits" by one
// artist in different folders stay apart. Hex of the first 16 bytes of a
// sha256.
func albumKey(serial, relPath, albumArtist, album string) string {
	h := sha256.New()
	for _, part := range []string{strings.ToLower(albumArtist), strings.ToLower(album), serial, folderOf(relPath)} {
		_, _ = io.WriteString(h, part)
		_, _ = h.Write([]byte{0})
	}
	return hex.EncodeToString(h.Sum(nil)[:16])
}

// titleFromName is a file's name without its extension, an untagged track's
// title.
func titleFromName(relPath string) string {
	name := path.Base(relPath)
	return strings.TrimSuffix(name, path.Ext(name))
}

// coverRank orders a folder image among the cover candidates; ok is false
// for a name that is not one.
func coverRank(name string) (int, bool) {
	lower := strings.ToLower(name)
	ext := path.Ext(lower)
	for b, base := range coverBaseNames {
		for e, want := range coverExtensions {
			if ext == want && strings.TrimSuffix(lower, ext) == base {
				return b*len(coverExtensions) + e, true
			}
		}
	}
	return 0, false
}

func nullInt(n int) sql.NullInt64 {
	return sql.NullInt64{Int64: int64(n), Valid: n > 0}
}

func boolInt(b bool) int64 {
	if b {
		return 1
	}
	return 0
}

// upsertParams builds a row from a file's tags, falling back to its name for
// the title and to the artist for the album artist.
func upsertParams(serial, relPath string, size, mtime int64, tags audiotagutil.Tags, cover folderCover) db.UpsertMusicTrackParams {
	title := cmp.Or(strings.TrimSpace(tags.Title), titleFromName(relPath))
	artist := strings.TrimSpace(tags.Artist)
	albumArtist := cmp.Or(strings.TrimSpace(tags.AlbumArtist), artist)
	album := strings.TrimSpace(tags.Album)
	params := db.UpsertMusicTrackParams{
		Serial:         serial,
		RelPath:        relPath,
		Size:           size,
		Mtime:          mtime,
		ScannerVersion: ScannerVersion,
		Title:          title,
		Artist:         artist,
		AlbumArtist:    albumArtist,
		Album:          album,
		AlbumKey:       albumKey(serial, relPath, albumArtist, album),
		Genre:          strings.TrimSpace(tags.Genre),
		TrackNo:        nullInt(tags.TrackNo),
		DiscNo:         nullInt(tags.DiscNo),
		Year:           nullInt(tags.Year),
		DurationMs:     sql.NullInt64{Int64: tags.Duration.Milliseconds(), Valid: tags.Duration > 0},
		DurationExact:  boolInt(tags.DurationExact),
	}
	switch {
	case tags.Picture != nil:
		params.CoverSource, params.CoverKey = "embedded", tags.Picture.SHA256
	case cover.key != "":
		params.CoverSource, params.CoverKey = "folder:"+cover.name, cover.key
	}
	return params
}

// trackFromRow is the public shape of a stored row.
func trackFromRow(row db.MusicTrack) Track {
	return Track{
		Serial:        row.Serial,
		RelPath:       row.RelPath,
		Title:         row.Title,
		Artist:        row.Artist,
		AlbumArtist:   row.AlbumArtist,
		Album:         row.Album,
		AlbumKey:      row.AlbumKey,
		Genre:         row.Genre,
		TrackNo:       int(row.TrackNo.Int64),
		DiscNo:        int(row.DiscNo.Int64),
		Year:          int(row.Year.Int64),
		DurationMs:    row.DurationMs.Int64,
		DurationExact: row.DurationExact != 0,
		HasCover:      row.CoverSource != "",
	}
}

// clampLimit bounds a caller's page to (0, MaxLimit], DefaultLimit for zero
// or less.
func clampLimit(limit int) int {
	if limit <= 0 {
		return DefaultLimit
	}
	return min(limit, MaxLimit)
}

// pageOf cuts one page out of a whole list.
func pageOf[T any](all []T, offset, limit int) []T {
	offset = min(max(offset, 0), len(all))
	end := min(offset+clampLimit(limit), len(all))
	return all[offset:end]
}

// sqlLower lowercases ASCII letters only, as SQLite's LOWER() does, so a
// non-admin's groups and order match the admin's SQL aggregate.
func sqlLower(s string) string {
	return strings.Map(func(r rune) rune {
		if 'A' <= r && r <= 'Z' {
			return r + ('a' - 'A')
		}
		return r
	}, s)
}

// minString is the smaller of two strings, taking b when a is unset. It is
// SQL's MIN() over a group, which picks the displayed casing.
func minString(a string, set bool, b string) string {
	if !set || b < a {
		return b
	}
	return a
}

// consider offers a track to a group's cover.
func (c *coverPick) consider(row db.MusicTrack) {
	hasCover := row.CoverSource != ""
	better := !c.set ||
		(hasCover && !c.hasCover) ||
		(hasCover == c.hasCover && (row.RelPath < c.relPath || (row.RelPath == c.relPath && row.Serial < c.serial)))
	if better {
		*c = coverPick{set: true, hasCover: hasCover, serial: row.Serial, relPath: row.RelPath}
	}
}
