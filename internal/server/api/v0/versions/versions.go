// Package v0_versions serves /api/v0/versions, a file's version history (#1173): taking a snapshot, listing a
// file's versions, downloading one, restoring one, and deleting a named one. None of it is admin-only: listing and
// downloading need read access to the file, and snapshot, restore and delete need write access.
package v0_versions

import (
	"github.com/autobutler-org/quark/pkg/util/fileversionutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

// VersionJSON is one snapshot of a file. fileversionutil builds it; the alias
// is what the endpoint annotations name it by.
type VersionJSON = fileversionutil.Version

// SnapshotJSON answers a snapshot request.
type SnapshotJSON struct {
	// Version holds the file's content: the new snapshot, or the existing one
	// that already did when nothing was copied.
	Version VersionJSON `json:"version"`
	// Created is false when the content matched the newest snapshot, or an
	// auto snapshot came too soon after the last.
	Created bool `json:"created"`
}

// ListVersionsJSON is a file's versions, newest first.
type ListVersionsJSON struct {
	Versions []VersionJSON `json:"versions"`
}

// RestoreJSON answers a restore.
type RestoreJSON struct {
	// Restored is the version the file now holds.
	Restored VersionJSON `json:"restored"`
	// Backup holds what the file held before; restoring it undoes this one.
	Backup VersionJSON `json:"backup"`
}

func NewRouter() serverutil.Router {
	return &router{}
}
