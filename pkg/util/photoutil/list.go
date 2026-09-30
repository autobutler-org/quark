package photoutil

import (
	"context"
	"fmt"
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
	// for a photo whose date is known (#2592).
	TakenAt int64 `json:"takenAt,omitempty"`
}

// ListPhotosParams describes one page of the photo library.
type ListPhotosParams struct {
	// Ctx bounds the VFS listing.
	Ctx context.Context
	// FS lists through the VFS. Nil falls back to walking the managed devices.
	FS vfs.VFS
	// Storage enumerates the managed devices for the fallback walk.
	Storage *storageutil.StorageService
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
	// Queries reads the capture dates SortTaken orders by. Nil sorts SortTaken
	// by the date added alone.
	Queries *db.Queries
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
	Queries *db.Queries
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
	var allPhotos []PhotoSummary

	if params.FS != nil {
		// VFS path: recursive image listing.
		serialFilter := []string{}
		if params.Serial != "" {
			serialFilter = []string{params.Serial}
		}
		infos, listErr := params.FS.List(params.Ctx, "", &vfs.ListFilter{
			Recursive:    true,
			MimePrefix:   "image/",
			SerialFilter: serialFilter,
		})
		if listErr != nil {
			return ListPhotosResult{}, listErr
		}
		for _, fi := range infos {
			if fi.IsDir || !params.Access.Check(fi.DeviceSerial, fi.Path, accessutil.Read).Readable {
				continue
			}
			allPhotos = append(allPhotos, PhotoSummary{
				RelPath:  fi.Path,
				FileName: fi.Name,
				Size:     fi.Size,
				MTime:    fi.ModTime.Unix(),
				Serial:   fi.DeviceSerial,
			})
		}
	} else {
		// Fallback: walk the managed devices.
		devices, err := params.Storage.GetManagedRoots()
		if err != nil {
			return ListPhotosResult{}, err
		}
		if params.Serial != "" {
			filtered := make([]storageutil.ManagedDevice, 0, 1)
			for _, d := range devices {
				deviceSerial := ""
				if d.UsbInfo != nil {
					deviceSerial = d.UsbInfo.GetSerial()
				}
				if deviceSerial == params.Serial {
					filtered = append(filtered, d)
				}
			}
			devices = filtered
		}
		for _, device := range devices {
			deviceSerial := ""
			if device.UsbInfo != nil {
				deviceSerial = device.UsbInfo.GetSerial()
			}
			photos, err := FindAllPhotosRecursively(device.FilesDir)
			if err != nil {
				continue
			}
			for _, photo := range photos {
				if !params.Access.Check(deviceSerial, photo.RelPath, accessutil.Read).Readable {
					continue
				}
				info := photo.FileInfo
				allPhotos = append(allPhotos, PhotoSummary{
					RelPath:      photo.RelPath,
					FileName:     info.Name(),
					Size:         info.Size(),
					MTime:        info.ModTime().Unix(),
					Serial:       deviceSerial,
					HasLiveVideo: photo.HasLiveVideo,
				})
			}
		}
	}

	if params.Sort == SortTaken && params.Queries != nil {
		taken, err := TakenDates(TakenDatesParams{Ctx: params.Ctx, Queries: params.Queries})
		if err != nil {
			return ListPhotosResult{}, err
		}
		for i, photo := range allPhotos {
			key := DuplicatePhoto{DeviceSerial: photo.Serial, RelPath: accessutil.Canonical(photo.RelPath)}
			if t, ok := taken.Dates[key]; ok {
				allPhotos[i].TakenAt = t.Unix()
			}
		}
	}
	sortPhotos(allPhotos, params.Sort, params.Order)

	total := len(allPhotos)
	if params.Offset >= total {
		return ListPhotosResult{
			Photos: []PhotoSummary{},
			Total:  total,
			Offset: params.Offset,
			Limit:  params.Limit,
		}, nil
	}

	return ListPhotosResult{
		Photos: allPhotos[params.Offset:min(params.Offset+params.Limit, total)],
		Total:  total,
		Offset: params.Offset,
		Limit:  params.Limit,
	}, nil
}
