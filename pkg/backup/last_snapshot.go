package backup

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// lastSnapshotFilename is the file in the Quark's data directory that holds
// when the last snapshot backup completed, as one RFC 3339 time. The job store
// is in memory and the manifest lives on a drive that may be unplugged, so
// neither can answer that after a restart.
const lastSnapshotFilename = "last-snapshot-backup"

// RecordSnapshot records that a snapshot backup completed at the given time.
func RecordSnapshot(dataDir string, at time.Time) error {
	if err := storageutil.WriteFileAtomic(
		filepath.Join(dataDir, lastSnapshotFilename),
		strings.NewReader(at.UTC().Format(time.RFC3339)),
	); err != nil {
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
func LastSnapshot(dataDir string) (time.Time, error) {
	f, err := os.Open(filepath.Join(dataDir, lastSnapshotFilename))
	if os.IsNotExist(err) {
		return time.Time{}, nil
	}
	if err != nil {
		return time.Time{}, fmt.Errorf("open snapshot backup record: %w", err)
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, 64))
	if err != nil {
		return time.Time{}, fmt.Errorf("read snapshot backup record: %w", err)
	}
	at, err := time.Parse(time.RFC3339, strings.TrimSpace(string(data)))
	if err != nil {
		// A record nobody can read is no record: the nudge that follows
		// prompts the backup that rewrites it, where an error would keep
		// failing until then.
		return time.Time{}, nil
	}
	return at, nil
}
