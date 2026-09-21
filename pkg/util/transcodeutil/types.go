package transcodeutil

import (
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// handler carries what the transcode job kind needs at run time.
type handler struct {
	storage   *storageutil.StorageService
	database  *db.DatabaseSqlc
	bus       *eventbus.Bus
	transcode TranscodeFunc
}

// source is a transcode's input, resolved against the device files directory.
type source struct {
	filesDir string
	fullPath string
	relPath  string
}

// processStart is roughly when this process began. A staged file older than
// it was left by a process that is gone; a newer one may belong to a job
// running right now in another lane.
var processStart = time.Now()
