package transcodeutil

import (
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// handler carries what the transcode job kind needs at run time.
type handler struct {
	storage  *storageutil.StorageService
	registry vfs.Registry
	database *db.DatabaseSqlc
	bus      *eventbus.Bus
	remux    RemuxFunc
}

// source is a transcode's input: a file in the files namespace of the device
// with serial, at relPath, which the VFS has cleaned.
type source struct {
	fsys    vfs.VFS
	serial  string
	relPath string
}

// processStart is roughly when this process began. A staged file older than
// it was left by a process that is gone; a newer one may belong to a job
// running right now.
var processStart = time.Now()
