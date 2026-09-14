package photoutil

import (
	"context"
	"fmt"
	"slices"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
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

// ListDuplicates groups the indexed photos that duplicate each other: exact
// matches by SHA-256 content hash, near matches by perceptual dHash distance.
// It reads the hashes the thumbnail pipeline stored, so a photo that has no
// thumbnail yet cannot appear in a group.
func ListDuplicates(params ListDuplicatesParams) (ListDuplicatesResult, error) {
	var groups []DuplicateGroup
	readable := func(serial, relPath string) bool {
		return params.Access.Check(serial, relPath, accessutil.Read).Readable
	}

	// --- Exact duplicates (same SHA-256 content hash) ---
	exactRows, err := params.Queries.ListExactDuplicates(params.Ctx)
	if err != nil {
		return ListDuplicatesResult{}, fmt.Errorf("failed to list exact duplicates: %w", err)
	}

	// Group rows by content_hash.
	exactGroups := map[string][]DuplicatePhoto{}
	for _, row := range exactRows {
		if !row.ContentHash.Valid || !readable(row.DeviceSerial, row.RelPath) {
			continue
		}
		key := row.ContentHash.String
		exactGroups[key] = append(exactGroups[key], DuplicatePhoto{
			DeviceSerial: row.DeviceSerial,
			RelPath:      row.RelPath,
		})
	}
	for _, photos := range exactGroups {
		if len(photos) > 1 {
			groups = append(groups, DuplicateGroup{Kind: "exact", Photos: photos})
		}
	}

	// --- Near-duplicates (dHash Hamming distance <= threshold) ---
	// ListNearDuplicates returns rows ordered by dhash. Adjacent rows in
	// sorted order are the most likely near-duplicate candidates — compare
	// each consecutive pair and group matches.
	nearRows, err := params.Queries.ListNearDuplicates(params.Ctx)
	if err != nil {
		return ListDuplicatesResult{}, fmt.Errorf("failed to list near duplicates: %w", err)
	}

	// Simple O(n²) cluster detection for a small library. For large libraries
	// a VP-tree or BK-tree would be more efficient, but n is bounded by the
	// number of photos indexed and this runs server-side rarely.
	seen := map[int]bool{}
	for i := 0; i < len(nearRows); i++ {
		if seen[i] || !nearRows[i].Dhash.Valid {
			continue
		}
		var group []DuplicatePhoto
		group = append(group, DuplicatePhoto{
			DeviceSerial: nearRows[i].DeviceSerial,
			RelPath:      nearRows[i].RelPath,
		})
		for j := i + 1; j < len(nearRows); j++ {
			if !nearRows[j].Dhash.Valid {
				continue
			}
			d := HammingDistanceHex(nearRows[i].Dhash.String, nearRows[j].Dhash.String)
			if d >= 0 && d <= params.Threshold {
				group = append(group, DuplicatePhoto{
					DeviceSerial: nearRows[j].DeviceSerial,
					RelPath:      nearRows[j].RelPath,
				})
				seen[j] = true
			}
		}
		// Clustered over every photo, then trimmed to what the caller can read,
		// so a group means the same thing to everyone who can see it.
		group = slices.DeleteFunc(group, func(p DuplicatePhoto) bool {
			return !readable(p.DeviceSerial, p.RelPath)
		})
		if len(group) > 1 {
			groups = append(groups, DuplicateGroup{Kind: "near", Photos: group})
		}
		seen[i] = true
	}

	if groups == nil {
		groups = []DuplicateGroup{}
	}

	return ListDuplicatesResult{Groups: groups}, nil
}
