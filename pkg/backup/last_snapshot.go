package backup

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/autobutler-org/quark/internal/db"
)

// lastSnapshotKey is the settings row that holds when the last snapshot
// backup completed, as the JSON string of one RFC 3339 UTC time. The job's row
// is pruned with the rest of the job history and the manifest lives on a
// drive that may be unplugged, so neither can be relied on to answer that. In
// the database every instance reads the same answer (#3083).
const lastSnapshotKey = "lastSnapshotBackup"

// lastSnapshotFilename is the file in the Quark's data directory that held
// the same time, bare, before it moved into the database.
const lastSnapshotFilename = "last-snapshot-backup"

// RecordSnapshot records that a snapshot backup completed at the given time.
func RecordSnapshot(ctx context.Context, queries *db.Queries, at time.Time) error {
	if err := queries.SetSetting(ctx, db.SetSettingParams{Key: lastSnapshotKey, Value: lastSnapshotValue(at)}); err != nil {
		return fmt.Errorf("record snapshot backup: %w", err)
	}
	return nil
}

// LastSnapshot returns when the last snapshot backup completed, or the zero
// time when none is on record.
//
// ponytail: a Quark whose last backup predates this record reads as never
// backed up until its next snapshot. If that matters, fall back to the
// manifest's mtime on the connected snapshot-backup devices.
func LastSnapshot(ctx context.Context, queries *db.Queries) (time.Time, error) {
	value, err := queries.GetSetting(ctx, lastSnapshotKey)
	if errors.Is(err, sql.ErrNoRows) {
		return time.Time{}, nil
	}
	if err != nil {
		return time.Time{}, fmt.Errorf("read snapshot backup record: %w", err)
	}
	var at time.Time
	if err := json.Unmarshal([]byte(value), &at); err != nil {
		// A record nobody can read is no record: the nudge that follows
		// prompts the backup that rewrites it, where an error would keep
		// failing until then.
		return time.Time{}, nil
	}
	return at, nil
}

// ImportLastSnapshot moves the record file of an older Quark into the
// database and renames it last-snapshot-backup.imported so the next start
// finds nothing to do. A time already in the database is kept, and a file
// that holds no time is retired without importing anything, as it read as no
// record. No file is nothing to do.
func ImportLastSnapshot(ctx context.Context, queries *db.Queries, dataDir string) error {
	path := filepath.Join(dataDir, lastSnapshotFilename)
	f, err := os.Open(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("open snapshot backup record: %w", err)
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, 64))
	if err != nil {
		return fmt.Errorf("read snapshot backup record: %w", err)
	}
	if at, err := time.Parse(time.RFC3339, strings.TrimSpace(string(data))); err == nil {
		if err := queries.AddSetting(ctx, db.AddSettingParams{Key: lastSnapshotKey, Value: lastSnapshotValue(at)}); err != nil {
			return fmt.Errorf("import snapshot backup record: %w", err)
		}
	}
	// Another instance may have renamed it first; its row is the same one.
	if err := os.Rename(path, path+".imported"); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return fmt.Errorf("retire snapshot backup record file: %w", err)
	}
	return nil
}

// lastSnapshotValue is a completion time as the settings row stores it. Like
// the file before it, it keeps whole seconds.
func lastSnapshotValue(at time.Time) string {
	return strconv.Quote(at.UTC().Format(time.RFC3339))
}
