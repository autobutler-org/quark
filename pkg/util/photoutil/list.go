package photoutil

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"path"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

const defaultLimit = 50
const maxLimit = 200

// Sort field and order values ListPhotos and the album-items listing accept.
// An unrecognized value falls back to SortAdded / OrderDesc, the historical
// fixed order (#2509). SortTaken orders by the EXIF capture date, where one is
// known, and by the date added otherwise (#2592).
const (
	SortAdded = "added"
	SortName  = "name"
	SortTaken = "taken"

	OrderAsc  = "asc"
	OrderDesc = "desc"
)

// PhotoSummary is a photo file as the listing endpoints report it.
type PhotoSummary struct {
	RelPath      string `json:"relPath"`
	FileName     string `json:"fileName"`
	Size         int64  `json:"size"`
	MTime        int64  `json:"mtime"`
	Serial       string `json:"serial"`
	HasLiveVideo bool   `json:"hasLiveVideo,omitempty"`
	// TakenAt is the EXIF capture date in Unix seconds, set under SortTaken
	// for a photo whose date is known (#2592). A photo whose EXIF has not been
	// read yet is read by the listing itself, so a fresh upload carries its
	// date the first time it is listed (#3356).
	TakenAt int64 `json:"takenAt,omitempty"`
}

// ListPhotosParams describes one page of the photo library.
type ListPhotosParams struct {
	// Ctx bounds the VFS listing.
	Ctx context.Context
	// Registry lists through the VFS, one namespace per device.
	Registry vfs.Registry
	// Serial restricts the listing to one device, empty for all of them.
	Serial string
	// Access drops the photos the caller cannot read, before sorting and
	// paging, so a page stays full and Total counts only what they can see.
	Access accessutil.Access
	// Sort is SortAdded (default), SortName or SortTaken; Order is OrderDesc
	// (default) or OrderAsc. Anything else is treated as the default for that
	// field.
	Sort  string
	Order string
	// Queries reads the capture dates SortTaken orders by, and records the
	// ones the listing reads. Nil sorts SortTaken by the date added alone.
	Queries db.Querier
	// Offset and Limit page the sorted result.
	Offset int
	Limit  int
}

// ListPhotosResult is a page of photos plus the pagination metadata.
type ListPhotosResult struct {
	Photos []PhotoSummary
	Total  int
	Offset int
	Limit  int
	// PendingDates counts the photos, across the whole library, whose EXIF
	// has still not been read under SortTaken: this listing read as many as
	// it may, and they sort by their date added until a later one reads them
	// (#3356).
	PendingDates int
}

// ParsePagination reads the offset and limit query parameters, falling back to
// the defaults for anything missing or unparseable and clamping the page size
// to the maximum.
func ParsePagination(offsetRaw, limitRaw string) (offset, limit int) {
	offset = 0
	if parsed, err := strconv.Atoi(offsetRaw); err == nil && parsed >= 0 {
		offset = parsed
	}
	limit = defaultLimit
	if parsed, err := strconv.Atoi(limitRaw); err == nil && parsed > 0 {
		limit = parsed
	}
	return offset, min(limit, maxLimit)
}

// ParseSort reads the sort query parameter, falling back to SortAdded for
// anything unrecognized.
func ParseSort(raw string) string {
	switch raw {
	case SortName, SortTaken:
		return raw
	}
	return SortAdded
}

// TakenDatesParams names where capture dates are stored.
type TakenDatesParams struct {
	Ctx     context.Context
	Queries db.Querier
}

// TakenDatesResult maps a photo, keyed by device serial and canonical path,
// to its EXIF capture date.
type TakenDatesResult struct {
	Dates map[DuplicatePhoto]time.Time
}

// TakenDates reads every capture date the photo scan has recorded (#2592).
// A photo missing from the map has no date, or has not been read yet.
func TakenDates(params TakenDatesParams) (TakenDatesResult, error) {
	rows, err := params.Queries.ListPhotoTakenAt(params.Ctx)
	if err != nil {
		return TakenDatesResult{}, fmt.Errorf("list capture dates: %w", err)
	}
	dates := make(map[DuplicatePhoto]time.Time, len(rows))
	for _, row := range rows {
		key := DuplicatePhoto{DeviceSerial: row.DeviceSerial, RelPath: row.RelPath}
		dates[key] = row.TakenAt.Time
	}
	return TakenDatesResult{Dates: dates}, nil
}

// ParseOrder reads the order query parameter, falling back to OrderDesc for
// anything unrecognized.
func ParseOrder(raw string) string {
	if raw == OrderAsc {
		return OrderAsc
	}
	return OrderDesc
}

// deviceSerial is the device a listed file is on, read from the namespace that
// listed it, which every namespace reports, and from the file's own device
// fields otherwise.
func deviceSerial(fi vfs.FileInfo) string {
	if serial, ok := vfs.FilesNamespaceSerial(fi.Namespace); ok {
		return serial
	}
	return fi.DeviceSerial
}

// liveVideoKey keys a file by device and its path without the extension,
// lowercased, so a photo finds its Live Photo video whatever case either
// extension is spelled in.
func liveVideoKey(serial, p string) DuplicatePhoto {
	canonical := accessutil.Canonical(p)
	return DuplicatePhoto{DeviceSerial: serial, RelPath: strings.ToLower(strings.TrimSuffix(canonical, path.Ext(canonical)))}
}

// sortPhotos orders photos by sortBy and order, defaulting to newest-first by
// modification time — the fixed order ListPhotos used before #2509 — for a
// zero-value or unrecognized sortBy/order. SortTaken orders by TakenAt,
// standing in the modification time for a photo without one.
func sortPhotos(photos []PhotoSummary, sortBy, order string) {
	ascending := order == OrderAsc
	if sortBy == SortName {
		sort.Slice(photos, func(i, j int) bool {
			ni := strings.ToLower(photos[i].FileName)
			nj := strings.ToLower(photos[j].FileName)
			if ascending {
				return ni < nj
			}
			return ni > nj
		})
		return
	}
	key := func(p PhotoSummary) int64 { return p.MTime }
	if sortBy == SortTaken {
		key = func(p PhotoSummary) int64 {
			if p.TakenAt != 0 {
				return p.TakenAt
			}
			return p.MTime
		}
	}
	sort.Slice(photos, func(i, j int) bool {
		if ascending {
			return key(photos[i]) < key(photos[j])
		}
		return key(photos[i]) > key(photos[j])
	})
}

// ListPhotos returns one page of the photo library, sorted by Sort and Order.
//
// TODO: For very large collections, an index/cache would be needed instead
// of walking the entire directory tree on every request. The walk itself is
// fast — it's downstream operations like thumbnail generation that are slow.
func ListPhotos(params ListPhotosParams) (ListPhotosResult, error) {
	serialFilter := []string{}
	if params.Serial != "" {
		serialFilter = []string{params.Serial}
	}
	// Videos are listed too, only to mark the photos that are Live Photos.
	infos, err := vfs.ListDevices(vfs.ListDevicesParams{
		Ctx:      params.Ctx,
		Registry: params.Registry,
		Filter:   &vfs.ListFilter{Recursive: true, SerialFilter: serialFilter},
	})
	if err != nil {
		return ListPhotosResult{}, err
	}
	liveVideos := map[DuplicatePhoto]bool{}
	for _, fi := range infos {
		if !fi.IsDir && strings.HasPrefix(fi.MimeType, "video/") {
			liveVideos[liveVideoKey(deviceSerial(fi), fi.Path)] = true
		}
	}
	var allPhotos []PhotoSummary
	for _, fi := range infos {
		serial := deviceSerial(fi)
		if fi.IsDir || !strings.HasPrefix(fi.MimeType, "image/") ||
			!params.Access.Check(serial, fi.Path, accessutil.Read).Readable {
			continue
		}
		allPhotos = append(allPhotos, PhotoSummary{
			RelPath:      fi.Path,
			FileName:     fi.Name,
			Size:         fi.Size,
			MTime:        fi.ModTime.Unix(),
			Serial:       serial,
			HasLiveVideo: canHaveLiveVideo(fi.Name) && liveVideos[liveVideoKey(serial, fi.Path)],
		})
	}

	pending := 0
	if params.Sort == SortTaken && params.Queries != nil {
		if pending, err = fillTakenDates(params, allPhotos); err != nil {
			return ListPhotosResult{}, err
		}
	}
	sortPhotos(allPhotos, params.Sort, params.Order)

	total := len(allPhotos)
	page := []PhotoSummary{}
	if params.Offset < total {
		page = allPhotos[params.Offset:min(params.Offset+params.Limit, total)]
	}
	return ListPhotosResult{
		Photos:       page,
		Total:        total,
		Offset:       params.Offset,
		Limit:        params.Limit,
		PendingDates: pending,
	}, nil
}

// takenDatesPerList caps the EXIF headers one SortTaken listing reads, so a
// library copied in all at once is dated over a few listings rather than
// holding up the first one.
var takenDatesPerList = 200

// fillTakenDates sets TakenAt on every photo whose capture date is known, and
// reads the EXIF of up to takenDatesPerList photos never read before, newest
// first, recording what it finds (#3356). Until now a photo was dated only
// when its thumbnail rendered or the startup backfill reached it, so a fresh
// upload listed under its upload date. It returns how many photos are left
// unread. A photo that cannot be read is logged and not counted: the next
// listing tries it again, but a client waiting on the count never waits on a
// file that will not open.
func fillTakenDates(params ListPhotosParams, photos []PhotoSummary) (int, error) {
	taken, err := TakenDates(TakenDatesParams{Ctx: params.Ctx, Queries: params.Queries})
	if err != nil {
		return 0, err
	}
	states, err := params.Queries.ListPhotoHashStates(params.Ctx)
	if err != nil {
		return 0, fmt.Errorf("list photo hashes: %w", err)
	}
	stored := make(map[DuplicatePhoto]bool, len(states))
	checked := make(map[DuplicatePhoto]bool, len(states))
	for _, row := range states {
		key := DuplicatePhoto{DeviceSerial: row.DeviceSerial, RelPath: row.RelPath}
		stored[key] = true
		checked[key] = row.TakenChecked
	}

	var unread []int
	for i, photo := range photos {
		key := DuplicatePhoto{DeviceSerial: photo.Serial, RelPath: accessutil.Canonical(photo.RelPath)}
		if t, ok := taken.Dates[key]; ok {
			photos[i].TakenAt = t.Unix()
		} else if !checked[key] && !storageutil.IsTrashPath(key.RelPath) {
			unread = append(unread, i)
		}
	}
	// The newest are the likeliest to be what was just uploaded.
	sort.SliceStable(unread, func(a, b int) bool { return photos[unread[a]].MTime > photos[unread[b]].MTime })

	for n, i := range unread {
		if n == takenDatesPerList {
			return len(unread) - n, nil
		}
		if err := params.Ctx.Err(); err != nil {
			return 0, err
		}
		key := DuplicatePhoto{DeviceSerial: photos[i].Serial, RelPath: accessutil.Canonical(photos[i].RelPath)}
		at, err := recordTakenAt(params, key, stored[key])
		if err != nil {
			log.Printf("[photos] read capture date of %q (serial=%q): %v", key.RelPath, key.DeviceSerial, err)
			continue
		}
		if at.Valid {
			photos[i].TakenAt = at.Time.Unix()
		}
	}
	return 0, nil
}

// recordTakenAt reads one photo's capture date through its device's namespace
// and stores it, on the photo's row when it has one and on a new row of its
// own otherwise. A new row holds no hashes; BackfillHashes fills them in, as
// it does for any photo missing them, and so too when a thumbnail stored this
// photo's hashes between the listing's read of the rows and this write.
func recordTakenAt(params ListPhotosParams, photo DuplicatePhoto, stored bool) (sql.NullTime, error) {
	fsys, err := DeviceFS(params.Registry, photo.DeviceSerial)
	if err != nil {
		return sql.NullTime{}, err
	}
	f, err := fsys.Open(params.Ctx, photo.RelPath)
	if err != nil {
		return sql.NullTime{}, err
	}
	defer f.Close()
	takenAt, err := readTakenAt(f, photo.RelPath)
	if err != nil {
		return sql.NullTime{}, err
	}
	if stored {
		err = params.Queries.SetPhotoTakenAt(params.Ctx, db.SetPhotoTakenAtParams{
			TakenAt: takenAt, DeviceSerial: photo.DeviceSerial, RelPath: photo.RelPath,
		})
	} else {
		err = params.Queries.UpsertPhotoHash(params.Ctx, db.UpsertPhotoHashParams{
			DeviceSerial: photo.DeviceSerial, RelPath: photo.RelPath,
			TakenAt: takenAt, TakenChecked: true,
		})
	}
	if err != nil {
		return sql.NullTime{}, fmt.Errorf("store capture date: %w", err)
	}
	return takenAt, nil
}
