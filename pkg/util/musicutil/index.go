package musicutil

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"io"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/audiotagutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

func indexTrack(params IndexTrackParams) (IndexTrackResult, error) {
	relPath := accessutil.Canonical(params.RelPath)
	if !indexable(relPath) {
		return IndexTrackResult{}, nil
	}
	fi, err := params.FS.Stat(params.Ctx, relPath)
	if err != nil {
		return IndexTrackResult{}, err
	}
	if fi.IsDir {
		return IndexTrackResult{}, nil
	}
	return indexFile(params.Ctx, params.DB, params.FS, params.Serial, relPath, fi, &folderCovers{})
}

// indexFile reads one audio file's tags and upserts its row. A tag the
// reader refuses still writes a row, titled from the file name; only a file
// that cannot be opened or read is an error.
func indexFile(ctx context.Context, sqlDB *sql.DB, fsys vfs.VFS, serial, relPath string, fi vfs.FileInfo, covers *folderCovers) (IndexTrackResult, error) {
	f, err := fsys.Open(ctx, relPath)
	if err != nil {
		return IndexTrackResult{}, err
	}
	read, err := audiotagutil.Read(audiotagutil.ReadParams{File: f, Size: fi.Size})
	_ = f.Close()
	var result IndexTrackResult
	switch {
	case errors.Is(err, audiotagutil.ErrMalformed),
		errors.Is(err, audiotagutil.ErrTagTooLarge),
		errors.Is(err, audiotagutil.ErrUnsupported):
		result.TagsUnreadable = true
	case err != nil:
		return IndexTrackResult{}, err
	}
	var cover folderCover
	if read.Tags.Picture == nil {
		cover = covers.lookup(ctx, fsys, folderOf(relPath))
	}
	params := upsertParams(serial, relPath, fi.Size, fi.ModTime.Unix(), read.Tags, cover)
	if _, err := db.NewQueries(sqlDB).UpsertMusicTrack(ctx, params); err != nil {
		return IndexTrackResult{}, err
	}
	result.Indexed = true
	return result, nil
}

// lookup returns the folder's cover image, reading it only when the folder
// differs from the last one asked about.
func (c *folderCovers) lookup(ctx context.Context, fsys vfs.VFS, folder string) folderCover {
	if c.found && c.folder == folder {
		return c.cover
	}
	c.folder, c.found, c.cover = folder, true, findFolderCover(ctx, fsys, folder)
	return c.cover
}

// findFolderCover picks the best-ranked cover image in a folder and hashes
// it. An image above audiotagutil.MaxTagBytes is passed over, and any error
// means no cover: art is never worth failing a track for.
func findFolderCover(ctx context.Context, fsys vfs.VFS, folder string) folderCover {
	entries, err := fsys.List(ctx, folder, nil)
	if err != nil {
		return folderCover{}
	}
	best, bestRank := vfs.FileInfo{}, -1
	for _, entry := range entries {
		if entry.IsDir || entry.Size > audiotagutil.MaxTagBytes {
			continue
		}
		if rank, ok := coverRank(entry.Name); ok && (bestRank < 0 || rank < bestRank) {
			best, bestRank = entry, rank
		}
	}
	if bestRank < 0 {
		return folderCover{}
	}
	f, err := fsys.Open(ctx, accessutil.Canonical(folder+"/"+best.Name))
	if err != nil {
		return folderCover{}
	}
	defer func() { _ = f.Close() }()
	h := sha256.New()
	if _, err := io.Copy(h, io.LimitReader(f, audiotagutil.MaxTagBytes)); err != nil {
		return folderCover{}
	}
	return folderCover{name: best.Name, key: hex.EncodeToString(h.Sum(nil))}
}

func backfillDevice(params BackfillDeviceParams) (BackfillDeviceResult, error) {
	var result BackfillDeviceResult
	if params.FS == nil {
		return result, nil
	}
	ctx := params.Ctx
	q := db.NewQueries(params.DB)
	stored, err := q.ListMusicTrackScanStates(ctx, params.Serial)
	if err != nil {
		return result, err
	}
	// unseen starts as every stored row and loses each one the walk reaches.
	unseen := make(map[string]scanState, len(stored))
	for _, row := range stored {
		unseen[row.RelPath] = scanState{size: row.Size, mtime: row.Mtime, version: row.ScannerVersion}
	}

	covers := &folderCovers{}
	walkErr := vfs.Walk(ctx, params.FS, "", func(fi vfs.FileInfo) error {
		relPath := accessutil.Canonical(fi.Path)
		if fi.IsDir {
			// A row at a path that is now a folder is stale. Drop it before
			// the walk reaches what is inside, which keeps its own rows.
			if _, ok := unseen[relPath]; ok {
				delete(unseen, relPath)
				if err := q.DeleteMusicTrack(ctx, db.DeleteMusicTrackParams{Serial: params.Serial, RelPath: relPath}); err != nil {
					return err
				}
				result.Deleted++
			}
			return nil
		}
		if !indexable(relPath) {
			return nil
		}
		result.Scanned++
		state, known := unseen[relPath]
		delete(unseen, relPath)
		if known && state == (scanState{size: fi.Size, mtime: fi.ModTime.Unix(), version: ScannerVersion}) {
			result.Unchanged++
		} else {
			fileCtx, cancel := context.WithTimeout(ctx, FileTimeout)
			indexed, err := indexFile(fileCtx, params.DB, params.FS, params.Serial, relPath, fi, covers)
			cancel()
			switch {
			case err != nil:
				result.Failed++
			case indexed.TagsUnreadable:
				result.Indexed++
				result.Unreadable++
			default:
				result.Indexed++
			}
		}
		if params.Progress != nil {
			params.Progress(result)
		}
		return nil
	})
	switch {
	case errors.Is(walkErr, vfs.ErrNotFound):
		// A device that is not mounted keeps its rows; DropDevice is how a
		// drive that went away loses them.
		return result, nil
	case walkErr != nil:
		return result, fmt.Errorf("music backfill of serial %q: %w", params.Serial, walkErr)
	}
	for relPath := range unseen {
		if err := q.DeleteMusicTrack(ctx, db.DeleteMusicTrackParams{Serial: params.Serial, RelPath: relPath}); err != nil {
			return result, err
		}
		result.Deleted++
	}
	return result, nil
}

func deletePath(params DeletePathParams) error {
	return db.NewQueries(params.DB).DeleteMusicTracksUnder(params.Ctx, db.DeleteMusicTracksUnderParams{
		Serial:  params.Serial,
		RelPath: accessutil.Canonical(params.RelPath),
	})
}

func movePath(params MovePathParams) (MovePathResult, error) {
	oldPath, newPath := accessutil.Canonical(params.OldPath), accessutil.Canonical(params.NewPath)
	if oldPath == newPath || oldPath == "" || newPath == "" {
		return MovePathResult{}, nil
	}
	var result MovePathResult
	err := db.InTx(params.Ctx, params.DB, func(q db.Querier) error {
		// The destination now holds the moved file; whatever was indexed
		// there is gone.
		if err := q.DeleteMusicTracksUnder(params.Ctx, db.DeleteMusicTracksUnderParams{Serial: params.Serial, RelPath: newPath}); err != nil {
			return err
		}
		if err := q.MoveMusicTracks(params.Ctx, db.MoveMusicTracksParams{
			Serial: params.Serial, OldRelPath: oldPath, NewRelPath: newPath,
		}); err != nil {
			return err
		}
		moved, err := q.ListMusicTracksUnder(params.Ctx, db.ListMusicTracksUnderParams{Serial: params.Serial, RelPath: newPath})
		if err != nil {
			return err
		}
		for _, row := range moved {
			if err := q.SetMusicTrackAlbumKey(params.Ctx, db.SetMusicTrackAlbumKeyParams{
				ID:       row.ID,
				AlbumKey: albumKey(params.Serial, row.RelPath, row.AlbumArtist, row.Album),
			}); err != nil {
				return err
			}
		}
		result.Moved = len(moved)
		return nil
	})
	return result, err
}

func dropDevice(params DropDeviceParams) error {
	return db.NewQueries(params.DB).DeleteMusicTracksBySerial(params.Ctx, params.Serial)
}
