package v0_versions

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/fileversionutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// errNoAccess is what a caller hears about a file they may not see. It reads
// the same as a file that does not exist, because to them it does not.
var errNoAccess = errors.New("file not found")

// errReadOnly is what a caller hears when they may see a file but not change
// it.
var errReadOnly = errors.New("you do not have permission to change this")

// errNoFilesNamespace reports a server with no files namespace to keep
// versions in.
var errNoFilesNamespace = errors.New("version history is unavailable")

// prepare resolves what every versions handler needs: the dependencies, the
// files namespace, and the caller's access to the file at p at level. A
// non-nil response is the answer to send instead.
func prepare(c *gin.Context, p string, level accessutil.Level) (deputil.Dependencies, vfs.VFS, *serverutil.Response) {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return nil, nil, serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return nil, nil, serverutil.InternalServerError(err)
	}
	// Versions live on the internal device only, so there is no serial.
	check := access.Check("", p, level)
	if !check.Readable {
		return nil, nil, serverutil.NotFound(errNoAccess)
	}
	if !check.Allowed {
		return nil, nil, serverutil.Forbidden(errReadOnly)
	}
	fsys, err := fileutil.FilesVFS(deps.VFSRegistry(), "")
	if err != nil {
		return nil, nil, serverutil.InternalServerError(errNoFilesNamespace)
	}
	return deps, fsys, nil
}

// callerID is the signed-in user, recorded as a snapshot's author.
func callerID(c *gin.Context) int64 {
	principal, _ := ctxutil.Get[accessutil.Principal](c, "principal")
	return principal.UserID
}

// versionError maps what fileversionutil reports onto status codes.
func versionError(err error) *serverutil.Response {
	switch {
	case errors.Is(err, fileversionutil.ErrNotFound):
		return serverutil.NotFound(err)
	case errors.Is(err, fileversionutil.ErrTooLarge):
		return serverutil.NewResponse().WithStatusCode(http.StatusRequestEntityTooLarge).WithError(err)
	case errors.Is(err, fileversionutil.ErrInvalidPath),
		errors.Is(err, fileversionutil.ErrInvalidID),
		errors.Is(err, fileversionutil.ErrInvalidLabel),
		errors.Is(err, fileversionutil.ErrInvalidKind),
		errors.Is(err, fileversionutil.ErrNotAFile),
		errors.Is(err, fileversionutil.ErrNotNamed):
		return serverutil.BadRequest(err)
	default:
		return serverutil.InternalServerError(err)
	}
}
