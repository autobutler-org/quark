package v0_vault

import (
	"errors"
	"fmt"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// updateVaultFolder godoc
// @Summary Update a vault folder
// @Description Renames or re-parents one folder.
// @Tags vault
// @Accept json
// @Produce json
// @Param id path int true "Folder ID"
// @Param body body createFolderRequest true "Replacement folder fields"
// @Success 200 {object} object "id of the updated folder"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /vault/folders/{id} [put]
func updateVaultFolder(c *gin.Context) *serverutil.Response {
	deps, errResp := getDeps(c)
	if errResp != nil {
		return errResp
	}

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid id"))
	}

	var req createFolderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request: %w", err))
	}

	result, err := vaultutil.UpdateFolder(c.Request.Context(), vaultutil.UpdateFolderParams{
		Queries: deps.VaultDB().Queries,
		ID:      id,
		Fields:  req.fields(),
	})
	if errors.Is(err, vaultutil.ErrFolderNotFound) {
		return serverutil.NotFound(err)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(gin.H{
		"id": result.ID,
	})
}

var updateVaultFolderRoute = serverutil.ApiRoute("PUT", "/vault/folders/:id", updateVaultFolder)
