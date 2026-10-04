package server

import (
	"context"
	"log"

	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// backfillPhotoHashes hashes the library photos that duplicate detection has
// no complete hashes for (#1666). Run once at startup, like
// backfillContentIndex: the thumbnail paths hash a photo only when they
// render it, so without this pass a photo whose thumbnail was cached before
// this build is never compared. Best-effort; everything is logged.
func backfillPhotoHashes(deps deputil.Dependencies) {
	dbConn := deps.Database()
	if dbConn == nil || dbConn.Queries == nil {
		return
	}
	var fsys vfs.VFS
	if reg := deps.VFSRegistry(); reg != nil {
		if registered, ok := reg.Get("files"); ok {
			fsys = registered
		}
	}
	res, err := photoutil.BackfillHashes(photoutil.BackfillHashesParams{
		Ctx:         context.Background(),
		Queries:     dbConn.Queries,
		FS:          fsys,
		Storage:     deps.StorageService(),
		IOSemaphore: deps.IOSemaphore().For(iosemutil.Decode),
	})
	if err != nil {
		log.Printf("[photo-hashes] backfill: %v", err)
		return
	}
	log.Printf("[photo-hashes] backfill: scanned %d, hashed %d, failed %d", res.Scanned, res.Hashed, res.Failed)
}
