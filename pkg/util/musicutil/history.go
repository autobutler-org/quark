package musicutil

import (
	"cmp"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"path"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// playsKey is the per-account key a track's plays are stored under, which is
// what keeps one account's history out of another's.
func playsKey(userID int64) string {
	return "music.plays." + strconv.FormatInt(userID, 10)
}

// cleanTrackPath spells a path the way the library stores it: slash
// separated with no leading slash.
func cleanTrackPath(p string) string {
	return strings.TrimPrefix(path.Clean("/"+p), "/")
}

// libraryTrack is the caller-readable library row for a file, or
// ErrTrackNotFound.
func libraryTrack(ctx context.Context, sqlDB *sql.DB, access accessutil.Access, serial, relPath string) (db.MusicTrack, error) {
	row, err := db.NewQueries(sqlDB).GetMusicTrack(ctx, db.GetMusicTrackParams{Serial: serial, RelPath: relPath})
	if errors.Is(err, sql.ErrNoRows) || (err == nil && !readable(access, row)) {
		return db.MusicTrack{}, ErrTrackNotFound
	}
	return row, err
}

func recordPlay(params RecordPlayParams) (RecordPlayResult, error) {
	relPath := cleanTrackPath(params.RelPath)
	if _, err := libraryTrack(params.Ctx, params.DB, params.Access, params.Serial, relPath); err != nil {
		return RecordPlayResult{}, err
	}
	namespace, key := vfs.FilesNamespace(params.Serial), playsKey(params.Access.Principal().UserID)
	// ponytail: read-then-write without a transaction, so two plays posted at
	// the same instant by one account can count once; fine for a play counter.
	meta, err := params.Store.Get(params.Ctx, namespace, relPath)
	if err != nil {
		return RecordPlayResult{}, err
	}
	var plays Plays
	if raw, ok := meta[key]; ok {
		if err := json.Unmarshal(raw, &plays); err != nil {
			return RecordPlayResult{}, fmt.Errorf("decode plays: %w", err)
		}
	}
	plays.Count++
	plays.LastPlayedAt = time.Now().UTC().Truncate(time.Second)
	raw, err := json.Marshal(plays)
	if err != nil {
		return RecordPlayResult{}, err
	}
	err = params.Store.Set(params.Ctx, namespace, relPath, map[string]json.RawMessage{key: raw})
	return RecordPlayResult{Plays: plays}, err
}

func listHistory(params ListHistoryParams) (ListHistoryResult, error) {
	var order func(a, b PlayedTrack) int
	switch params.Sort {
	case HistoryRecent, "":
		order = func(a, b PlayedTrack) int { return b.LastPlayedAt.Compare(a.LastPlayedAt) }
	case HistoryMost:
		order = func(a, b PlayedTrack) int { return cmp.Compare(b.PlayCount, a.PlayCount) }
	default:
		return ListHistoryResult{}, ErrInvalidHistorySort
	}
	key := playsKey(params.Access.Principal().UserID)
	played := []PlayedTrack{}
	for _, serial := range params.Serials {
		entries, err := params.Store.Query(params.Ctx, vfs.FilesNamespace(serial), key, nil)
		if err != nil {
			return ListHistoryResult{}, err
		}
		for _, entry := range entries {
			var plays Plays
			if err := json.Unmarshal(entry.Meta[key], &plays); err != nil {
				continue // a row this code did not write counts as unplayed
			}
			row, err := libraryTrack(params.Ctx, params.DB, params.Access, serial, entry.Path)
			if errors.Is(err, ErrTrackNotFound) {
				continue // the file is gone, or no longer the caller's to see
			}
			if err != nil {
				return ListHistoryResult{}, err
			}
			played = append(played, PlayedTrack{Track: trackFromRow(row), PlayCount: plays.Count, LastPlayedAt: plays.LastPlayedAt})
		}
	}
	slices.SortFunc(played, func(a, b PlayedTrack) int {
		return cmp.Or(order(a, b), b.LastPlayedAt.Compare(a.LastPlayedAt), cmp.Compare(a.Track.Title, b.Track.Title))
	})
	return ListHistoryResult{Tracks: pageOf(played, 0, params.Limit)}, nil
}
