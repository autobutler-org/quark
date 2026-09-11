package v0_files

import (
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"

	"github.com/gin-gonic/gin"
)

type StatFileJSON struct {
	IsDir    bool   `json:"isDir"`
	FileType string `json:"fileType"` // Kept for older clients; route viewers by file name instead
	Name     string `json:"name"`
}

// statFile godoc
// @Summary Stat a file or directory
// @Description Returns filesystem metadata for the given files-relative path: whether it is a directory and its file type. Useful for deep-link resolution when the path extension alone is ambiguous (e.g. a folder named "things.qdoc").
// @Tags files
// @Produce json
// @Param filePath query string true "Files-relative path to stat"
// @Param serial query string false "Device serial number"
// @Success 200 {object} StatFileJSON
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /files/stat [get]
func statFile(c *gin.Context) *serverutil.Response {
	filePath := c.Query("filePath")

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	// VFS path: always preferred when available.
	if reg := deps.VFSRegistry(); reg != nil {
		if fsys, ok := reg.Get("files"); ok {
			fi, err := fsys.Stat(c.Request.Context(), filePath)
			if err != nil {
				if err == vfs.ErrNotFound {
					return serverutil.NotFound(err)
				}
				return serverutil.InternalServerError(err)
			}
			return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(StatFileJSON{
				IsDir:    fi.IsDir,
				FileType: string(storageutil.DetermineFileTypeFromPath(fi.Path)),
				Name:     fi.Name,
			})
		}
	}

	// Fallback: StorageService direct call.
	serial := c.Query("serial")
	result, err := deps.StorageService().StatFile(storageutil.StatFileParams{
		FilePath:     filePath,
		DeviceSerial: serial,
	})
	if err != nil {
		return serverutil.NotFound(err)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(StatFileJSON{
		IsDir:    result.IsDir,
		FileType: string(result.FileType),
		Name:     result.Name,
	})
}

var statFileRoute = serverutil.ApiRoute(
	"GET", "/files/stat", statFile,
)
