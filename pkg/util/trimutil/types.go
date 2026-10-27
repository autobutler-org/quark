package trimutil

import (
	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// handler carries what the trim job kind needs at run time.
type handler struct {
	storage  *storageutil.StorageService
	registry vfs.Registry
	database *db.DatabaseSqlc
	bus      *eventbus.Bus
	trimFile TrimFileFunc
}

// source is a trim's input: a file in the files namespace of the device with
// serial, at relPath, which the VFS has cleaned.
type source struct {
	fsys    vfs.VFS
	serial  string
	relPath string
}
