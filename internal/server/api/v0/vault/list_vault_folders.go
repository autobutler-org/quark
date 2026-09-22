package v0_vault

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// listVaultFolders godoc
// @Summary List vault folders
// @Description Returns every folder. Folder names are not encrypted.
// @Tags vault
// @Produce json
// @Success 200 {object} object "folders: array of vaultutil.Folder"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /vault/folders [get]
func listVaultFolders(c *gin.Context) *serverutil.Response {
	deps, errResp := getDeps(c)
	if errResp != nil {
		return errResp
	}

	result, err := vaultutil.ListFolders(c.Request.Context(), vaultutil.ListFoldersParams{
		Queries: deps.VaultDB().Queries,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(gin.H{
		"folders": result.Folders,
	})
}

var listVaultFoldersRoute = serverutil.ApiRoute("GET", "/vault/folders", listVaultFolders)
