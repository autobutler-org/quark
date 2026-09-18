package v0_trash

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// errTrashReadOnly is what a caller hears about a trashed item they can see
// but not put back or delete.
var errTrashReadOnly = errors.New("you do not have permission to change this")

// loadAccess reads what the caller may reach, once per request (#1905).
// requireAuth sets the principal; a request that arrives without one gets the
// zero principal, which is denied everything.
func loadAccess(c *gin.Context, deps deputil.Dependencies) (accessutil.Access, error) {
	principal, _ := ctxutil.Get[accessutil.Principal](c, "principal")
	result, err := accessutil.Load(accessutil.LoadParams{
		Ctx:       c.Request.Context(),
		Database:  deps.Database(),
		Storage:   deps.StorageService(),
		Principal: principal,
	})
	return result.Access, err
}

// trashError maps the trash service's errors onto status codes: a malformed
// name or path, or a listing of something that is not a folder, is the
// caller's fault, an unknown device or item is 404, and an item
// that cannot go back where it came from is 409.
func trashError(err error) *serverutil.Response {
	switch {
	case errors.Is(err, storageutil.ErrInvalidTrashName), errors.Is(err, storageutil.ErrInvalidTrashPath),
		errors.Is(err, storageutil.ErrNotATrashFolder):
		return serverutil.BadRequest(err)
	case errors.Is(err, storageutil.ErrDeviceNotFound), errors.Is(err, storageutil.ErrTrashItemNotFound):
		return serverutil.NotFound(err)
	case errors.Is(err, storageutil.ErrRestoreConflict):
		return serverutil.Conflict(err)
	}
	return serverutil.InternalServerError(err)
}

// bindTrashItems reads a restore or delete body, which must name at least one item.
func bindTrashItems(bind func(any) error) (trashItemsRequest, error) {
	var req trashItemsRequest
	if err := bind(&req); err != nil {
		return req, errors.New("invalid request body")
	}
	if len(req.Items) == 0 {
		return req, errors.New("items must name at least one item")
	}
	return req, nil
}
