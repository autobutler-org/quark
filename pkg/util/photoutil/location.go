package photoutil

import (
	"database/sql"
	"fmt"
	"math"
	"sort"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// exifFacts is what one EXIF read records about a photo: when and where it
// was taken, each NULL when the EXIF does not say.
type exifFacts struct {
	takenAt   sql.NullTime
	latitude  sql.NullFloat64
	longitude sql.NullFloat64
}

// setParams records facts on photo's existing row.
func (f exifFacts) setParams(photo DuplicatePhoto) db.SetPhotoTakenAtParams {
	return db.SetPhotoTakenAtParams{
		TakenAt: f.takenAt, Latitude: f.latitude, Longitude: f.longitude,
		DeviceSerial: photo.DeviceSerial, RelPath: photo.RelPath,
	}
}

// ValidPosition is the GPS position in data, rounded to the 6 decimal places
// the metadata panel shows, when there is one a map can place (#3557): a
// finite latitude within ±90 and longitude within ±180, and not 0,0, which is
// what a camera writes when it has no fix. ok is false for anything else, so
// a photo with no or malformed GPS stays off the map rather than landing in
// the Gulf of Guinea.
func ValidPosition(data *ExifData) (lat, lon float64, ok bool) {
	if data == nil || !data.HasGPS {
		return 0, 0, false
	}
	lat, lon = RoundTo(data.Latitude, 6), RoundTo(data.Longitude, 6)
	switch {
	case math.IsNaN(lat) || math.IsNaN(lon) || math.IsInf(lat, 0) || math.IsInf(lon, 0):
		return 0, 0, false
	case lat < -90 || lat > 90 || lon < -180 || lon > 180:
		return 0, 0, false
	case lat == 0 && lon == 0:
		return 0, 0, false
	}
	return lat, lon, true
}

// LocationsParams names the library whose photo positions to report.
type LocationsParams struct {
	// List is the library listing, Access included: only what it lists is
	// reported or counted. Offset, Limit, Sort and Query are ignored.
	List ListPhotosParams
}

// LocationPoint is one photo placed on the map.
type LocationPoint struct {
	Serial   string  `json:"serial"`
	RelPath  string  `json:"relPath"`
	FileName string  `json:"fileName"`
	Lat      float64 `json:"lat"`
	Lon      float64 `json:"lon"`
	// TakenAt is the EXIF capture date in Unix seconds, 0 when unknown.
	TakenAt int64 `json:"takenAt,omitempty"`
	// MTime is when the file was last written, in Unix seconds, the date a
	// photo with no capture date goes by.
	MTime int64 `json:"mtime"`
}

// LocationsResult is every readable photo with a GPS position, and how the
// rest of the library stands.
type LocationsResult struct {
	// Points are the placed photos, newest first, ties by serial then path.
	Points []LocationPoint `json:"points"`
	// Total is the photos and videos the caller can read.
	Total int `json:"total"`
	// Located is len(Points); Unlocated is Total - Located, the photos read
	// that have no position plus those still waiting to be read.
	Located   int `json:"located"`
	Unlocated int `json:"unlocated"`
	// Pending counts the photos among Unlocated whose EXIF the index has not
	// read yet (#3556), so the view can say why they are missing.
	Pending int `json:"pending"`
}

// Locations reports where the caller's photos were taken, from the GPS
// positions the index stored from their EXIF (#3557). It is a view of the
// existing library: nothing is read from or written to a photo. A photo the
// caller cannot read is neither placed nor counted, the same rule
// [ListPhotos] applies, since the listing is where the points come from.
func Locations(params LocationsParams) (LocationsResult, error) {
	list := params.List
	list.Offset, list.Limit, list.Sort, list.Query = 0, math.MaxInt, SortAdded, ""
	library, err := ListPhotos(list)
	if err != nil {
		return LocationsResult{}, fmt.Errorf("list photos: %w", err)
	}
	type entry struct {
		photo PhotoSummary
		key   DuplicatePhoto
	}
	readable := make(map[DuplicatePhoto]PhotoSummary, len(library.Photos))
	var entries []entry
	for _, photo := range library.Photos {
		key := DuplicatePhoto{DeviceSerial: photo.Serial, RelPath: accessutil.Canonical(photo.RelPath)}
		if storageutil.IsTrashPath(key.RelPath) {
			continue
		}
		readable[key] = photo
		entries = append(entries, entry{photo: photo, key: key})
	}

	locations, err := list.Queries.ListPhotoLocations(list.Ctx)
	if err != nil {
		return LocationsResult{}, fmt.Errorf("list photo locations: %w", err)
	}
	states, err := list.Queries.ListPhotoHashStates(list.Ctx)
	if err != nil {
		return LocationsResult{}, fmt.Errorf("list photo hashes: %w", err)
	}
	checked := make(map[DuplicatePhoto]bool, len(states))
	for _, row := range states {
		checked[DuplicatePhoto{DeviceSerial: row.DeviceSerial, RelPath: row.RelPath}] = row.TakenChecked
	}

	result := LocationsResult{Points: []LocationPoint{}, Total: len(entries)}
	placed := make(map[DuplicatePhoto]bool, len(locations))
	for _, row := range locations {
		key := DuplicatePhoto{DeviceSerial: row.DeviceSerial, RelPath: row.RelPath}
		photo, ok := readable[key]
		if !ok || placed[key] {
			continue
		}
		lat, lon, ok := ValidPosition(&ExifData{
			HasGPS: true, Latitude: row.Latitude.Float64, Longitude: row.Longitude.Float64,
		})
		if !ok {
			continue
		}
		placed[key] = true
		point := LocationPoint{
			Serial: photo.Serial, RelPath: photo.RelPath, FileName: photo.FileName,
			Lat: lat, Lon: lon, MTime: photo.MTime,
		}
		if row.TakenAt.Valid {
			point.TakenAt = row.TakenAt.Time.Unix()
		}
		result.Points = append(result.Points, point)
	}
	for _, e := range entries {
		if !placed[e.key] && !checked[e.key] {
			result.Pending++
		}
	}
	sort.Slice(result.Points, func(i, j int) bool {
		a, b := result.Points[i], result.Points[j]
		if da, dbb := pointDate(a), pointDate(b); da != dbb {
			return da > dbb
		}
		if a.Serial != b.Serial {
			return a.Serial < b.Serial
		}
		return a.RelPath < b.RelPath
	})
	result.Located = len(result.Points)
	result.Unlocated = result.Total - result.Located
	return result, nil
}

// pointDate is the date a point sorts by: its capture date, else its mtime.
func pointDate(p LocationPoint) int64 {
	if p.TakenAt != 0 {
		return p.TakenAt
	}
	return p.MTime
}
