// Package bundleutil writes and reads a Quark bundle (#3838): one tar archive
// holding an install's database rows and its files, which an uninitialized
// Quark starts from. The database is a SQLite file at the bundle's quark.db
// whichever engine the source or the target runs on (db.ExportDatabase and
// db.ImportDatabase); the files are the data directory's files, trash and
// avatars directories, as they are on disk. Taking a bundle only reads the
// source.
package bundleutil

import (
	"context"
	"io"

	"github.com/autobutler-org/quark/internal/db"
)

// ExportParams names the install to bundle and where the bundle goes.
type ExportParams struct {
	// DataDir is the install's data directory, which holds quark.db on SQLite
	// and the files on either engine.
	DataDir string
	// Database is the database the install runs on.
	Database db.Config
	// Out receives the tar archive.
	Out io.Writer
}

// ExportResult reports what a bundle holds.
type ExportResult struct {
	Database db.CopyDatabaseResult
	// Files and Bytes count the regular files written and their content.
	Files int64
	Bytes int64
}

// Export writes a bundle of the install to Out: the database first, then the
// files. The database is one consistent snapshot; the files are read after
// it, so stop the service for a bundle in which the two agree.
func Export(ctx context.Context, params ExportParams) (ExportResult, error) {
	return export(ctx, params)
}

// ImportParams names the bundle and the new install it fills.
type ImportParams struct {
	// DataDir is the new install's data directory. The files go into it, and
	// on SQLite so does quark.db.
	DataDir string
	// Database is the database the new install runs on.
	Database db.Config
	// Bundle is the tar archive Export wrote.
	Bundle io.Reader
}

// ImportResult reports what an import filled.
type ImportResult struct {
	Database db.CopyDatabaseResult
	// Files and Bytes count the regular files written and their content.
	Files int64
	Bytes int64
}

// Import fills an uninitialized install from a bundle. A target with an
// account is refused before anything is written. The files are placed first
// and the database rows last, in one transaction, so a failed or interrupted
// import leaves the install without accounts, and running it again is safe:
// it writes the same files over the ones already placed.
func Import(ctx context.Context, params ImportParams) (ImportResult, error) {
	return importBundle(ctx, params)
}
