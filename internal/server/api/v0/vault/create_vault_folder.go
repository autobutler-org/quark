package v0_vault

import (
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// createVaultFolder godoc
// @Summary Create a vault folder
// @Description Adds a folder, optionally nested under a parent.
// @Tags vault
// @Accept json
// @Produce json
// @Param body body createFolderRequest true "Folder fields"
// @Success 200 {object} vaultutil.Folder
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /vault/folders [post]
func createVaultFolder(c *gin.Context) *serverutil.Response {
	deps, errResp := getDeps(c)
	if errResp != nil {
		return errResp
	}

	var req createFolderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request: %w", err))
	}

	result, err := vaultutil.CreateFolder(c.Request.Context(), vaultutil.CreateFolderParams{
		Queries: deps.VaultDB().Queries,
		Fields:  req.fields(),
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(result.Folder)
}

var createVaultFolderRoute = serverutil.ApiRoute("POST", "/vault/folders", createVaultFolder)
