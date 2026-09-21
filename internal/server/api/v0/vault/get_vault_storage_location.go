package v0_vault

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// getVaultStorageLocation godoc
// @Summary Get vault storage location
// @Description Returns which device the vault is stored on
// @Tags vault
// @Produce json
// @Success 200 {object} storageLocationResponse
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /vault/storage-location [get]
var getVaultStorageLocationRoute = serverutil.ApiRoute(
	"GET", "/vault/storage-location", func(c *gin.Context) *serverutil.Response {
		deps, errResp := getDeps(c)
		if errResp != nil {
			return errResp
		}

		result, err := vaultutil.GetLocation(c.Request.Context(), vaultutil.GetLocationParams{
			MainQueries: deps.Database().Queries,
			Storage:     deps.StorageService(),
		})
		if err != nil {
			return serverutil.InternalServerError(err)
		}

		return serverutil.Ok().WithData(storageLocationResponse{
			DeviceSerial:    result.DeviceSerial,
			IsExternal:      result.IsExternal,
			DeviceConnected: result.DeviceConnected,
			DeviceName:      result.DeviceName,
		})
	},
)
