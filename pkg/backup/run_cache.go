package backup

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// runCacheKeyPrefix, followed by a backup drive's serial, is the settings row
// holding the copies its run folders held when it was last scanned, as a JSON
// list of [RunCopy]. The run folders are the truth (#4037); the row only
// answers for a drive that is not attached. Built-in storage's serial is
// empty.
const runCacheKeyPrefix = "backupRuns:"

// DriveCopies returns the copies the backup drive with the given serial
// holds. An attached drive is scanned, and its cache rewritten, by
// [RefreshRunCache]. A drive with no files namespace is away, and its copies
// are those of its last scan; one never scanned has none. A scan that fails
// is logged and answered from the last scan too, which it leaves as it was,
// so one unreadable drive does not fail the status of every other.
func DriveCopies(ctx context.Context, queries db.Querier, registry vfs.Registry, serial string) ([]RunCopy, error) {
	if fsys, err := fileutil.FilesVFS(registry, serial); err == nil {
		copies, err := RefreshRunCache(ctx, queries, serial, fsys)
		if err == nil {
			return copies, nil
		}
		log.Printf("backup drive %q: scan runs: %v", serial, err)
	}
	return cachedRunCopies(ctx, queries, serial)
}

// RefreshRunCache scans the complete runs on fsys, the files namespace of the
// backup drive with the given serial, and returns the copies they hold: per
// data drive, the newest run naming it. It rewrites the drive's cache row with
// them every time, empty when the drive holds no run, so the row never
// outlives a run that was deleted.
func RefreshRunCache(ctx context.Context, queries db.Querier, serial string, fsys vfs.VFS) ([]RunCopy, error) {
	runs, err := ListRuns(ctx, fsys)
	if err != nil {
		return nil, err
	}
	copies := newestCopies(runs)
	value, err := json.Marshal(copies)
	if err != nil {
		return nil, err
	}
	if err := queries.SetSetting(ctx, db.SetSettingParams{Key: runCacheKeyPrefix + serial, Value: string(value)}); err != nil {
		return nil, fmt.Errorf("cache the runs of drive %q: %w", serial, err)
	}
	return copies, nil
}

// LastSnapshot returns when the newest complete run on any backup drive
// completed, or the zero time when no backup drive holds one. It reads each
// snapshot-backup drive's run cache, which every scan of the drive, every
// backup, delete and prune rewrites from the run folders, so it follows the
// folders and answers for a drive that is away (#4044).
func LastSnapshot(ctx context.Context, queries db.Querier) (time.Time, error) {
	backups, err := backupSerials(ctx, queries)
	if err != nil {
		return time.Time{}, err
	}
	var last time.Time
	for serial := range backups {
		copies, err := cachedRunCopies(ctx, queries, serial)
		if err != nil {
			return time.Time{}, err
		}
		for _, c := range copies {
			if c.CompletedAt.After(last) {
				last = c.CompletedAt
			}
		}
	}
	return last, nil
}

// cachedRunCopies reads the copies the drive held at its last scan. A drive
// never scanned, or a row nobody can read, has none.
func cachedRunCopies(ctx context.Context, queries db.Querier, serial string) ([]RunCopy, error) {
	value, err := queries.GetSetting(ctx, runCacheKeyPrefix+serial)
	if errors.Is(err, sql.ErrNoRows) {
		return []RunCopy{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read the cached runs of drive %q: %w", serial, err)
	}
	copies := []RunCopy{}
	if err := json.Unmarshal([]byte(value), &copies); err != nil {
		return []RunCopy{}, nil
	}
	return copies, nil
}

// newestCopies is, per drive the runs hold, the newest run holding it. runs
// is newest first, as [ListRuns] returns them.
func newestCopies(runs []Run) []RunCopy {
	copies := []RunCopy{}
	seen := map[string]bool{}
	for _, run := range runs {
		for _, d := range run.Drives {
			if seen[d.Serial] {
				continue
			}
			seen[d.Serial] = true
			copies = append(copies, RunCopy{Serial: d.Serial, Name: d.Name, CompletedAt: run.CompletedAt})
		}
	}
	return copies
}
