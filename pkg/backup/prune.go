package backup

import (
	"context"
	"errors"
	"fmt"
	"log"
	"math"
	"slices"

	"github.com/autobutler-org/quark/pkg/vfs"
)

// ErrNotEnoughSpace ends the message of a backup that does not fit on its
// drive even with every complete run but the newest deleted.
var ErrNotEnoughSpace = errors.New("delete old backups or use a bigger drive")

// planPrune is which runs to delete, oldest first, for need bytes to be free
// on a drive with free bytes free now. runs is oldest first. Each run counts
// as freeing its SizeBytes; one sharing hard-linked files with another frees
// less, so the caller deletes one run at a time and asks again. The last run,
// the newest, is never in the plan. ok is false when deleting every other run
// would still leave less than need.
func planPrune(runs []Run, free, need int64) (prune []Run, ok bool) {
	n := 0
	for ; free < need; n++ {
		if n >= len(runs)-1 {
			return nil, false
		}
		free += runs[n].SizeBytes
	}
	return runs[:n], true
}

// makeRoom deletes the oldest complete runs on target, one at a time, until
// it has need bytes free, the bytes the new run will copy (#4044). runs is
// newest first, as [ListRuns] returns them; the newest is never deleted, nor
// a run a restore is reading. A run that cannot fit even then fails with
// [ErrNotEnoughSpace] before anything is copied. A drive that cannot report
// its free space is not pruned.
func makeRoom(ctx context.Context, params SnapshotBackupParams, target vfs.VFS, runs []Run, need int64) error {
	serial := params.TargetDeviceSerial
	space, ok := target.(vfs.SpaceReporter)
	if !ok {
		log.Printf("snapshot backup: drive %q cannot report its free space; not pruning", serial)
		return nil
	}
	oldestFirst := slices.Clone(runs)
	slices.Reverse(oldestFirst)
	if params.Queries != nil {
		if reading, _ := restoringRun(ctx, params.Queries, serial); reading != "" {
			oldestFirst = slices.DeleteFunc(oldestFirst, func(r Run) bool { return r.Folder == reading })
		}
	}

	pruned := false
	defer func() {
		if pruned && params.Queries != nil {
			if _, err := RefreshRunCache(ctx, params.Queries, serial, target); err != nil {
				log.Printf("snapshot backup: %v", err)
			}
		}
	}()
	for {
		free, err := space.FreeSpace(ctx)
		if err != nil {
			log.Printf("snapshot backup: read the free space of drive %q: %v; not pruning", serial, err)
			return nil
		}
		plan, ok := planPrune(oldestFirst, int64(min(free, math.MaxInt64)), need)
		if !ok {
			name := params.Job.TargetName
			if name == "" {
				name = "the backup drive"
			}
			return fmt.Errorf("not enough space on %s for this backup: %w", name, ErrNotEnoughSpace)
		}
		if len(plan) == 0 {
			return nil
		}
		if err := removeRun(ctx, target, params.EventBus, serial, plan[0].Folder); err != nil {
			return err
		}
		pruned = true
		log.Printf("snapshot backup: pruned backup %s from drive %q for room: %d bytes free, %d needed", plan[0].Folder, serial, free, need)
		oldestFirst = oldestFirst[1:]
	}
}
