package photoutil

import (
	"context"
	"sort"
	"strconv"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

const defaultLimit = 50
const maxLimit = 200

// Sort field and order values ListPhotos and the album-items listing accept.
// An unrecognized value falls back to SortAdded / OrderDesc, the historical
// fixed order (#2509).
const (
	SortAdded = "added"
	SortName  = "name"

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
	// Sort is SortAdded (default) or SortName; Order is OrderDesc (default) or
	// OrderAsc. Anything else is treated as the default for that field.
	Sort  string
	Order string
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
	if raw == SortName {
		return SortName
	}
	return SortAdded
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
// zero-value or unrecognized sortBy/order.
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
	sort.Slice(photos, func(i, j int) bool {
		if ascending {
			return photos[i].MTime < photos[j].MTime
		}
		return photos[i].MTime > photos[j].MTime
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
