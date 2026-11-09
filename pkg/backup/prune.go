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
// drive even with every run [prunable] offers deleted.
var ErrNotEnoughSpace = errors.New("delete old backups or use a bigger drive")

// planPrune is which runs to delete, oldest first, for need bytes to be free
// on a drive with free bytes free now. runs is oldest first, and every one of
// them may be deleted. Each run counts as freeing its SizeBytes; one sharing
// hard-linked files with another frees less, so the caller deletes one run at
// a time and asks again. ok is false when deleting every run would still
// leave less than need.
func planPrune(runs []Run, free, need int64) (prune []Run, ok bool) {
	n := 0
	for ; free < need; n++ {
		if n >= len(runs) {
			return nil, false
		}
		free += runs[n].SizeBytes
	}
	return runs[:n], true
}

// prunable is the runs pruning may delete, oldest first, out of runs, newest
// first. It keeps the newest run, every run holding some drive's newest copy
// (the newest run whose manifest names that drive), and reading, the run a
// restore reads. A run may hold only some drives (#3984), so the newest run
// alone is not every drive's last copy, and the run a drive's next backup
// links its unchanged files from stays too.
func prunable(runs []Run, reading string) []Run {
	held := map[string]bool{}
	var out []Run
	for i, run := range runs {
		keep := i == 0 || run.Folder == reading
		for _, d := range run.Drives {
			if !held[d.Serial] {
				held[d.Serial], keep = true, true
			}
		}
		if !keep {
			out = append(out, run)
		}
	}
	slices.Reverse(out)
	return out
}

// makeRoom deletes the oldest complete runs on target, one at a time, until
// it has need bytes free, the bytes the new run will copy (#4044). runs is
// newest first, as [ListRuns] returns them; only what [prunable] offers is
// deleted. A run that cannot fit even then fails with
// [ErrNotEnoughSpace] before anything is copied. A drive that cannot report
// its free space is not pruned.
func makeRoom(ctx context.Context, params SnapshotBackupParams, target vfs.VFS, runs []Run, need int64) error {
	serial := params.TargetDeviceSerial
	space, ok := target.(vfs.SpaceReporter)
	if !ok {
		log.Printf("snapshot backup: drive %q cannot report its free space; not pruning", serial)
		return nil
	}
	reading := ""
	if params.Queries != nil {
		reading, _ = restoringRun(ctx, params.Queries, serial)
	}
	oldestFirst := prunable(runs, reading)

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
