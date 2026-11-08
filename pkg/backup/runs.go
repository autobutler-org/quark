package backup

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"log"
	"path"
	"slices"
	"strings"
	"time"

	"github.com/autobutler-org/quark/pkg/vfs"
)

// BackupsDir is the folder at the root of a backup drive that holds every
// snapshot run, one folder each (#4032). Every source walk leaves it out, so
// a drive's own backups are never copied as its files.
const BackupsDir = "backups"

// runFolderLayout names a run folder after the minute it started, in the
// Quark's local time. It has no ":" so FAT and exFAT accept it, and it sorts
// by time.
const runFolderLayout = "2006-01-02 15.04"

// partialSuffix ends the name of a run still being written:
// backups/.<run>.partial/, renamed to backups/<run>/ once it is complete.
const partialSuffix = ".partial"

// builtInFolder is the folder in a run holding built-in storage's files.
const builtInFolder = "Built-in storage"

// ErrRunNotFound reports a run the drive holds no complete backup under.
var ErrRunNotFound = errors.New("the drive holds no complete backup of that name")

// ListRuns returns the complete snapshot runs under backups/ on fsys, newest
// first. A folder still being written, or one with no readable manifest, is
// not a complete run and is left out. A drive with no backups/ folder has
// none.
func ListRuns(ctx context.Context, fsys vfs.VFS) ([]Run, error) {
	entries, err := fsys.List(ctx, BackupsDir, &vfs.ListFilter{SkipFolderSizes: true})
	if errors.Is(err, vfs.ErrNotFound) {
		return []Run{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("list %s: %w", BackupsDir, err)
	}
	runs := []Run{}
	for _, entry := range entries {
		// A disk-backed namespace may end a folder's name with "/" (#4043).
		name := strings.TrimSuffix(entry.Name, "/")
		if !entry.IsDir || strings.HasPrefix(name, ".") {
			continue
		}
		run, err := readRunHeader(ctx, fsys, name)
		if err != nil {
			continue
		}
		runs = append(runs, run)
	}
	slices.SortFunc(runs, func(a, b Run) int {
		if c := b.CompletedAt.Compare(a.CompletedAt); c != 0 {
			return c
		}
		return strings.Compare(b.Folder, a.Folder)
	})
	return runs, nil
}

// readRunHeader reads a run's completion time and drives from its manifest.
// They are written ahead of the file list, which grows with the drive, so the
// manifest is read as a stream of tokens and the list is never decoded.
func readRunHeader(ctx context.Context, fsys vfs.VFS, folder string) (Run, error) {
	f, err := fsys.Open(ctx, path.Join(BackupsDir, folder, manifestFilename))
	if err != nil {
		return Run{}, err
	}
	defer f.Close()
	run := Run{Folder: folder, Drives: []ManifestDrive{}}
	dec := json.NewDecoder(f)
	if tok, err := dec.Token(); err != nil || tok != json.Delim('{') {
		return Run{}, fmt.Errorf("manifest of %s is not an object", folder)
	}
	for dec.More() {
		tok, err := dec.Token()
		if err != nil {
			return Run{}, err
		}
		switch tok {
		case "completedAt":
			err = dec.Decode(&run.CompletedAt)
		case "drives":
			var drives []ManifestDrive
			if err = dec.Decode(&drives); err == nil {
				// The manifest is on the drive, so a folder it names must
				// be one entry in the run, never a path out of it.
				run.Drives = slices.DeleteFunc(drives, func(d ManifestDrive) bool {
					return d.Folder != path.Base(d.Folder) || strings.HasPrefix(d.Folder, ".")
				})
			}
		case "files":
			// Everything a run is listed by comes before the file list.
			return run, nil
		default:
			var skip json.RawMessage
			err = dec.Decode(&skip)
		}
		if err != nil {
			return Run{}, fmt.Errorf("manifest of %s: %w", folder, err)
		}
	}
	return run, nil
}

// resolveRun is the complete run named folder on fsys, or the newest one when
// folder is empty. Only a listed run is ever returned, so a name that would
// leave backups/ is [ErrRunNotFound] like any other unknown one. A drive with
// no complete run is [ErrNoSnapshot].
func resolveRun(ctx context.Context, fsys vfs.VFS, folder string) (Run, error) {
	runs, err := ListRuns(ctx, fsys)
	if err != nil {
		return Run{}, err
	}
	if len(runs) == 0 {
		return Run{}, ErrNoSnapshot
	}
	if folder == "" {
		return runs[0], nil
	}
	for _, run := range runs {
		if run.Folder == folder {
			return run, nil
		}
	}
	return Run{}, ErrRunNotFound
}

// runDir is the path of a complete run's folder on its drive.
func runDir(folder string) string {
	return path.Join(BackupsDir, folder)
}

// partialDir is the path a run is written under until it is complete.
func partialDir(folder string) string {
	return path.Join(BackupsDir, "."+folder+partialSuffix)
}

// newRunFolder names the run starting at now: its minute, then " (2)",
// " (3)" and so on when a run, complete or not, already has that name.
func newRunFolder(ctx context.Context, fsys vfs.VFS, now time.Time) (string, error) {
	base := now.Format(runFolderLayout)
	for n := 1; ; n++ {
		folder := base
		if n > 1 {
			folder = fmt.Sprintf("%s (%d)", base, n)
		}
		taken := false
		for _, p := range []string{runDir(folder), partialDir(folder)} {
			_, err := fsys.Stat(ctx, p)
			if err == nil {
				taken = true
				break
			}
			if !errors.Is(err, vfs.ErrNotFound) {
				return "", fmt.Errorf("check %s: %w", p, err)
			}
		}
		if !taken {
			return folder, nil
		}
	}
}

// removeStalePartials deletes the partial folders an earlier run left when
// the Quark stopped mid-backup. Only one backup writes to a drive at a time,
// so any partial folder found before a run starts is one nothing will finish.
// Best effort: what cannot be removed is logged and left.
func removeStalePartials(ctx context.Context, fsys vfs.VFS) {
	entries, err := fsys.List(ctx, BackupsDir, &vfs.ListFilter{SkipFolderSizes: true})
	if err != nil {
		return
	}
	for _, entry := range entries {
		name := strings.TrimSuffix(entry.Name, "/")
		if !entry.IsDir || !strings.HasPrefix(name, ".") || !strings.HasSuffix(name, partialSuffix) {
			continue
		}
		if err := fsys.Delete(ctx, path.Join(BackupsDir, name), vfs.DeleteOptions{Recursive: true}); err != nil {
			log.Printf("snapshot backup: remove stale %s: %v", name, err)
		}
	}
}

// skipBackupsDir leaves a source's backups/ folder out of a walk.
func skipBackupsDir(fi vfs.FileInfo) error {
	if fi.IsDir && strings.Trim(fi.Path, "/") == BackupsDir {
		return fs.SkipDir
	}
	return nil
}

// inBackupsDir reports whether p, a path from a drive's root, is the
// top-level backups/ folder or something in it.
func inBackupsDir(p string) bool {
	clean := strings.TrimPrefix(path.Clean("/"+p), "/")
	return clean == BackupsDir || strings.HasPrefix(clean, BackupsDir+"/")
}

// driveDirName is a source drive's folder in a run: "Built-in storage", or
// the drive's name and the first 8 characters of its serial, as
// "Photos (USB 90C82C65)".
func driveDirName(name, serial string) string {
	if serial == "" {
		return builtInFolder
	}
	safe := sanitizeName(name)
	if safe == "" {
		safe = "Drive"
	}
	return fmt.Sprintf("%s (USB %s)", safe, sanitizeName(serial[:min(len(serial), 8)]))
}
