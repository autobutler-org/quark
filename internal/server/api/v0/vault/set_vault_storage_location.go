package v0_vault

import (
	"errors"
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// setVaultStorageLocation godoc
// @Summary Change vault storage location
// @Description Migrates vault data to a different device. Requires vault unlocked and admin auth.
// @Tags vault
// @Accept json
// @Produce json
// @Param body body setStorageLocationRequest true "Migration request"
// @Success 200 {object} object
// @Failure 400 {object} serverutil.Response
// @Failure 401 {object} serverutil.Response
// @Failure 423 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Router /vault/storage-location [put]
var setVaultStorageLocationRoute = serverutil.ApiRoute(
	"PUT", "/vault/storage-location", func(c *gin.Context) *serverutil.Response {
		deps, _, errResp := requireUnlockedVault(c)
		if errResp != nil {
			return errResp
		}

		var req setStorageLocationRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			return serverutil.BadRequest(err)
		}

		ctx := c.Request.Context()

		if sessionUser, ok := ctxutil.Get[string](c, "username"); ok && sessionUser != req.Username {
			return serverutil.Unauthorized(fmt.Errorf("username does not match session"))
		}
		if _, _, err := authutil.ValidateBasicAuth(ctx, deps.Database().Queries, req.Username, req.Password); err != nil {
			return serverutil.Unauthorized(fmt.Errorf("invalid credentials"))
		}

		result, err := vaultutil.SetLocation(ctx, vaultutil.SetLocationParams{
			MainDB:       deps.Database(),
			VaultDB:      deps.VaultDB(),
			Storage:      deps.StorageService(),
			TargetSerial: req.TargetDeviceSerial,
		})
		switch {
		case errors.Is(err, vaultutil.ErrVaultAlreadyOnDevice):
			return serverutil.BadRequest(err)
		case errors.Is(err, vaultutil.ErrDeviceNotFound):
			return serverutil.BadRequest(fmt.Errorf("device %q not found or not connected", req.TargetDeviceSerial))
		case err != nil:
			return serverutil.InternalServerError(err)
		}

		if req.TargetDeviceSerial == "" {
			deps.ClearVaultDB()
		} else {
			deps.SetVaultDB(result.TargetDB)
		}

		return serverutil.Ok().WithData(gin.H{
			"deviceSerial": req.TargetDeviceSerial,
			"migrated":     true,
		})
	},
)
