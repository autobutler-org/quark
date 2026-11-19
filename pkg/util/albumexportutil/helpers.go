package albumexportutil

import (
	"context"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"path"
	"sort"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// plan lists every file the export copies, in the order it copies them: each
// chosen album's photos, then its sub-albums', then, for the library, the
// photos in no album. It reads the account's albums and pointers and the
// library listing, and writes nothing.
func plan(ctx context.Context, params ExportParams) ([]entry, error) {
	userID := params.Access.Principal().UserID
	albums, err := params.Queries.ListAlbums(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("list albums: %w", err)
	}
	byID := make(map[int64]db.PhotoAlbum, len(albums))
	children := map[int64][]db.PhotoAlbum{}
	var roots []db.PhotoAlbum
	for _, a := range albums {
		byID[a.ID] = a
		if a.ParentID.Valid {
			children[a.ParentID.Int64] = append(children[a.ParentID.Int64], a)
		} else {
			roots = append(roots, a)
		}
	}
	// albumPath is an album's name under its ancestors', as "Trips/Japan".
	// The depth bound keeps a parent cycle, which no write makes, finite.
	albumPath := func(a db.PhotoAlbum) string {
		parts := []string{a.Name}
		for i := 0; a.ParentID.Valid && i < len(albums); i++ {
			a = byID[a.ParentID.Int64]
			parts = append([]string{a.Name}, parts...)
		}
		return strings.Join(parts, "/")
	}

	items := map[int64][]db.PhotoAlbumItem{}
	member := map[photoKey][]string{}
	for _, a := range albums {
		listed, err := params.Queries.ListAlbumItems(ctx, a.ID)
		if err != nil {
			return nil, fmt.Errorf("list album %d: %w", a.ID, err)
		}
		// Oldest first, so the copies are numbered in the order they joined.
		for i := len(listed) - 1; i >= 0; i-- {
			item := listed[i]
			if !params.Access.Check(item.DeviceSerial, item.RelPath, accessutil.Read).Readable {
				continue
			}
			items[a.ID] = append(items[a.ID], item)
			key := photoKey{serial: item.DeviceSerial, relPath: accessutil.Canonical(item.RelPath)}
			member[key] = append(member[key], albumPath(a))
		}
	}
	for _, paths := range member {
		sort.Strings(paths)
	}

	chosen := roots
	if !params.Job.Library {
		chosen = chosenAlbums(params.Job.AlbumIDs, byID)
	}
	names := map[string]bool{strings.ToLower(ManifestName): true}
	if params.Job.Library {
		names[strings.ToLower(NotInAlbumFolder)] = true
	}
	var entries []entry
	var walk func(a db.PhotoAlbum, dir string)
	walk = func(a db.PhotoAlbum, dir string) {
		for _, item := range items[a.ID] {
			key := photoKey{serial: item.DeviceSerial, relPath: accessutil.Canonical(item.RelPath)}
			entries = append(entries, entry{
				serial:  item.DeviceSerial,
				relPath: key.relPath,
				dest:    freeName(names, dir, path.Base(key.relPath), true),
				albums:  member[key],
			})
		}
		for _, child := range children[a.ID] {
			walk(child, freeName(names, dir, folderName(child.Name), false))
		}
	}
	if !params.Job.Library && len(chosen) == 1 {
		walk(chosen[0], "")
	} else {
		for _, a := range chosen {
			walk(a, freeName(names, "", folderName(a.Name), false))
		}
	}

	if params.Job.Library {
		library, err := photoutil.ListPhotos(photoutil.ListPhotosParams{
			Ctx:           ctx,
			Registry:      params.Registry,
			Access:        params.Access,
			Limit:         libraryLimit,
			IncludeVideos: true,
			Sort:          photoutil.SortName,
			Order:         photoutil.OrderAsc,
		})
		if err != nil {
			return nil, fmt.Errorf("list the library: %w", err)
		}
		for _, photo := range library.Photos {
			rel := accessutil.Canonical(photo.RelPath)
			if len(member[photoKey{serial: photo.Serial, relPath: rel}]) > 0 {
				continue
			}
			dir := path.Join(NotInAlbumFolder, path.Dir(rel))
			entries = append(entries, entry{serial: photo.Serial, relPath: rel, dest: freeName(names, dir, path.Base(rel), true)})
		}
	}
	return entries, nil
}

// chosenAlbums is the albums asked for that still exist, in the order asked,
// leaving out any asked for twice or beneath another asked for: that one is
// exported inside its ancestor's folder already.
func chosenAlbums(ids []int64, byID map[int64]db.PhotoAlbum) []db.PhotoAlbum {
	asked := map[int64]bool{}
	for _, id := range ids {
		asked[id] = true
	}
	var chosen []db.PhotoAlbum
	seen := map[int64]bool{}
	for _, id := range ids {
		a, ok := byID[id]
		if !ok || seen[id] {
			continue
		}
		seen[id] = true
		beneath := false
		for p, i := a, 0; p.ParentID.Valid && i < len(byID); i++ {
			p = byID[p.ParentID.Int64]
			beneath = beneath || asked[p.ID]
		}
		if !beneath {
			chosen = append(chosen, a)
		}
	}
	return chosen
}

// freeName is name inside dir, numbered "name (2).jpg", "name (3).jpg", and so
// on past every path names already holds ignoring case, which it then holds
// too. A file keeps its extension after the number; a folder has none.
func freeName(names map[string]bool, dir, name string, isFile bool) string {
	stem, ext := name, ""
	if isFile {
		ext = path.Ext(name)
		stem = strings.TrimSuffix(name, ext)
	}
	candidate := path.Join(dir, name)
	for n := 2; names[strings.ToLower(candidate)]; n++ {
		candidate = path.Join(dir, fmt.Sprintf("%s (%d)%s", stem, n, ext))
	}
	names[strings.ToLower(candidate)] = true
	return candidate
}

// folderName is an album name as a folder name any drive accepts: the
// characters [folderUnsafe] lists, and control characters, become '_', and
// trailing dots and spaces go. A name left with nothing is "Album".
func folderName(name string) string {
	safe := strings.Map(func(r rune) rune {
		if r < 0x20 || strings.ContainsRune(folderUnsafe, r) {
			return '_'
		}
		return r
	}, name)
	safe = strings.TrimRight(strings.TrimSpace(safe), ". ")
	if safe == "" {
		return "Album"
	}
	return safe
}

// freeFolder is name inside parent, numbered "name (2)" and so on past every
// entry the folder already holds.
func freeFolder(ctx context.Context, fsys vfs.VFS, parent, name string) (string, error) {
	candidate := path.Join(parent, name)
	for n := 2; ; n++ {
		_, err := fsys.Stat(ctx, candidate)
		if errors.Is(err, vfs.ErrNotFound) {
			return candidate, nil
		}
		if err != nil {
			return "", fmt.Errorf("stat %s: %w", candidate, err)
		}
		candidate = path.Join(parent, fmt.Sprintf("%s (%d)", name, n))
	}
}

// prepareFolder makes the export folder and marks it, so the photo library
// never lists the copies beside their originals.
func prepareFolder(ctx context.Context, fsys vfs.VFS, rel string) error {
	if err := fsys.MkdirAll(ctx, rel); err != nil {
		return fmt.Errorf("create %s: %w", rel, err)
	}
	return photoutil.MarkDocumentMedia(ctx, fsys, rel)
}

// copyOne copies one original to target, replacing a copy an earlier run of
// the export left there.
func copyOne(ctx context.Context, params ExportParams, e entry, dst vfs.VFS, target string) error {
	src, err := fileutil.FilesVFS(params.Registry, e.serial)
	if err != nil {
		return err
	}
	if err := dst.MkdirAll(ctx, path.Dir(target)); err != nil {
		return err
	}
	if params.IOSemaphore != nil {
		if !params.IOSemaphore.AcquireDefault(ctx) {
			return fmt.Errorf("export: IO semaphore timeout copying %s", e.relPath)
		}
		defer params.IOSemaphore.Release()
	}
	return vfs.CopyBetween(ctx, src, e.relPath, dst, target, vfs.CopyOptions{})
}

// writeManifest writes rel from the CSV rows fill writes, streamed through a
// pipe rather than built up in memory. An error from fill aborts the write.
func writeManifest(ctx context.Context, fsys vfs.VFS, rel string, fill func(*csv.Writer) error) error {
	pr, pw := io.Pipe()
	go func() {
		w := csv.NewWriter(pw)
		err := fill(w)
		if err == nil {
			w.Flush()
			err = w.Error()
		}
		_ = pw.CloseWithError(err)
	}()
	err := fsys.Write(ctx, rel, pr, vfs.WriteOptions{ContentType: "text/csv"})
	// Unblock fill if the write stopped before reading everything.
	_ = pr.CloseWithError(err)
	if err != nil {
		return fmt.Errorf("write the manifest: %w", err)
	}
	return nil
}

// driveNames maps every managed drive's serial to its name, "" for the
// internal drive. A nil storage service names none.
func driveNames(storage *storageutil.StorageService) map[string]string {
	names := map[string]string{}
	if storage == nil {
		return names
	}
	managed, err := storage.GetManagedDevices()
	if err != nil {
		return names
	}
	for _, d := range managed {
		if d.UsbInfo != nil {
			names[d.UsbInfo.GetSerial()] = d.Name
		}
	}
	return names
}

// driveName is "Built-in storage" for serial "", what names calls any other
// serial, or the serial itself when it has no name.
func driveName(names map[string]string, serial string) string {
	switch {
	case serial == "":
		return "Built-in storage"
	case names[serial] != "":
		return names[serial]
	default:
		return serial
	}
}
