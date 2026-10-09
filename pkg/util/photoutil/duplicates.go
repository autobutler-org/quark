package photoutil

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"log"
	"slices"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

const (
	// defaultDuplicateThreshold is the Hamming distance under which two dHashes
	// count as near-duplicates.
	defaultDuplicateThreshold = 10
	// maxDuplicateThreshold is the largest threshold a caller may ask for.
	maxDuplicateThreshold = 20
)

// DuplicateGroup represents a group of photos that are exact or near
// duplicates of each other.
type DuplicateGroup struct {
	// Kind is "exact" (identical content hash) or "near" (perceptual hash
	// Hamming distance within the configured threshold).
	Kind string `json:"kind"`
	// Photos is the list of photos in this duplicate group.
	Photos []DuplicatePhoto `json:"photos"`
	// MaxDistance is the largest Hamming distance between any two of the
	// group's dHashes, over every photo clustered, including any the caller
	// cannot read. It is 0 for an exact group.
	MaxDistance int `json:"maxDistance"`
}

// DuplicatePhoto is a minimal photo reference inside a duplicate group.
type DuplicatePhoto struct {
	DeviceSerial string `json:"deviceSerial"`
	RelPath      string `json:"relPath"`
}

// ListDuplicatesParams selects how close two photos must be to be grouped.
type ListDuplicatesParams struct {
	// Ctx bounds the database reads.
	Ctx context.Context
	// Queries reads the stored content and perceptual hashes.
	Queries *db.Queries
	// Threshold is the Hamming distance under which two dHashes are grouped.
	Threshold int
	// Access drops the photos the caller cannot read from every group, and
	// with them any group left with fewer than two.
	Access accessutil.Access
	// Exists reports whether a photo is still on disk. A photo that is not is
	// left out and its hashes dropped, so a file deleted or moved outside
	// Quark stops showing up. Nil treats every photo as present.
	Exists func(serial, relPath string) bool
}

// ListDuplicatesResult is the set of duplicate groups found.
type ListDuplicatesResult struct {
	Groups []DuplicateGroup
}

// ParseDuplicateThreshold reads the threshold query parameter, falling back to
// the default for anything missing, unparseable, or out of range.
func ParseDuplicateThreshold(raw string) int {
	if raw == "" {
		return defaultDuplicateThreshold
	}
	var t int
	if _, err := fmt.Sscanf(raw, "%d", &t); err == nil && t >= 0 && t <= maxDuplicateThreshold {
		return t
	}
	return defaultDuplicateThreshold
}

// ListDuplicates groups the indexed photos that duplicate each other, each
// photo in at most one group (#1666). Photos with a perceptual dHash are
// clustered first by Hamming distance, identical files included, since they
// share a dHash; a cluster whose photos all share one SHA-256 is "exact", any
// other "near". Photos with no dHash are then grouped by content hash alone.
// Every exact group comes first, then the near groups, most similar first:
// lowest [DuplicateGroup.MaxDistance] first. Groups otherwise sort by their
// first photo, and the photos in a group by device, then path.
//
// It reads the hashes [StorePhotoHashes] stored: when a thumbnail is
// rendered or uploaded, and for the rest of the library by [BackfillHashes]
// at startup. Trashed photos never appear.
func ListDuplicates(params ListDuplicatesParams) (ListDuplicatesResult, error) {
	present := func(serial, relPath string) bool {
		if storageutil.IsTrashPath(relPath) {
			return false
		}
		if params.Exists == nil || params.Exists(serial, relPath) {
			return true
		}
		if err := params.Queries.DeletePhotoHash(params.Ctx, db.DeletePhotoHashParams{
			DeviceSerial: serial,
			RelPath:      relPath,
		}); err != nil {
			log.Printf("quark: duplicates: drop hashes of missing %q (serial=%q): %v", relPath, serial, err)
		}
		return false
	}
	readable := func(p DuplicatePhoto) bool {
		return params.Access.Check(p.DeviceSerial, p.RelPath, accessutil.Read).Readable
	}

	nearRows, err := params.Queries.ListNearDuplicates(params.Ctx)
	if err != nil {
		return ListDuplicatesResult{}, fmt.Errorf("failed to list near duplicates: %w", err)
	}
	exactRows, err := params.Queries.ListExactDuplicates(params.Ctx)
	if err != nil {
		return ListDuplicatesResult{}, fmt.Errorf("failed to list exact duplicates: %w", err)
	}

	type candidate struct {
		photo   DuplicatePhoto
		dhash   string
		content string
	}
	var hashed []candidate
	for _, row := range nearRows {
		if !row.Dhash.Valid || !present(row.DeviceSerial, row.RelPath) {
			continue
		}
		hashed = append(hashed, candidate{
			photo:   DuplicatePhoto{DeviceSerial: row.DeviceSerial, RelPath: row.RelPath},
			dhash:   row.Dhash.String,
			content: row.ContentHash.String,
		})
	}

	var groups []DuplicateGroup
	finish := func(members []candidate) {
		// Clustered over every photo, then trimmed to what the caller can
		// read, so a group means the same thing to everyone who can see it.
		var photos []DuplicatePhoto
		kind := "exact"
		for _, m := range members {
			if m.content == "" || m.content != members[0].content {
				kind = "near"
			}
			if readable(m.photo) {
				photos = append(photos, m.photo)
			}
		}
		if len(photos) < 2 {
			return
		}
		distance := 0
		if kind == "near" {
			for i, a := range members {
				for _, b := range members[i+1:] {
					distance = max(distance, HammingDistanceHex(a.dhash, b.dhash))
				}
			}
		}
		groups = append(groups, DuplicateGroup{Kind: kind, Photos: photos, MaxDistance: distance})
	}

	// Simple O(n²) cluster detection around a seed. For large libraries a
	// VP-tree or BK-tree would be more efficient, but n is bounded by the
	// photos indexed and this runs rarely.
	clustered := map[DuplicatePhoto]bool{}
	for i, seed := range hashed {
		if clustered[seed.photo] {
			continue
		}
		members := []candidate{seed}
		for _, other := range hashed[i+1:] {
			if clustered[other.photo] {
				continue
			}
			if d := HammingDistanceHex(seed.dhash, other.dhash); d >= 0 && d <= params.Threshold {
				members = append(members, other)
			}
		}
		if len(members) < 2 {
			continue
		}
		for _, m := range members {
			clustered[m.photo] = true
		}
		finish(members)
	}

	// Identical files that have no dHash, one that could not be decoded, say.
	byContent := map[string][]candidate{}
	var order []string
	for _, row := range exactRows {
		photo := DuplicatePhoto{DeviceSerial: row.DeviceSerial, RelPath: row.RelPath}
		if !row.ContentHash.Valid || clustered[photo] || !present(row.DeviceSerial, row.RelPath) {
			continue
		}
		key := row.ContentHash.String
		if _, ok := byContent[key]; !ok {
			order = append(order, key)
		}
		byContent[key] = append(byContent[key], candidate{photo: photo, content: key})
	}
	for _, key := range order {
		if members := byContent[key]; len(members) > 1 {
			finish(members)
		}
	}

	for _, g := range groups {
		slices.SortFunc(g.Photos, comparePhotos)
	}
	slices.SortFunc(groups, func(a, b DuplicateGroup) int {
		if a.Kind != b.Kind {
			if a.Kind == "exact" {
				return -1
			}
			return 1
		}
		if c := cmp.Compare(a.MaxDistance, b.MaxDistance); c != 0 {
			return c
		}
		return comparePhotos(a.Photos[0], b.Photos[0])
	})
	if groups == nil {
		groups = []DuplicateGroup{}
	}
	return ListDuplicatesResult{Groups: groups}, nil
}

// comparePhotos orders photos by device, then path.
func comparePhotos(a, b DuplicatePhoto) int {
	if c := strings.Compare(a.DeviceSerial, b.DeviceSerial); c != 0 {
		return c
	}
	return strings.Compare(a.RelPath, b.RelPath)
}

// ExistsIn is a [ListDuplicatesParams.Exists] that stats each photo through
// its device's namespace in registry. Only a photo the namespace reports
// missing is gone, along with every photo on a device with no namespace, as
// one unplugged; any other failure to stat keeps the photo.
func ExistsIn(ctx context.Context, registry vfs.Registry) func(serial, relPath string) bool {
	return func(serial, relPath string) bool {
		fsys, err := DeviceFS(registry, serial)
		if err != nil {
			return false
		}
		_, err = fsys.Stat(ctx, relPath)
		return !errors.Is(err, vfs.ErrNotFound)
	}
}
