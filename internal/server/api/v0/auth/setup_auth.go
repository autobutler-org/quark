package v0_auth

import (
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/gin-gonic/gin"
)

// setupAuth godoc
// @Summary First-boot user setup
// @Description Creates the owner account, with a home under users/ on the internal device that it owns. Can only be called once.
// @Tags auth
// @Accept json
// @Produce json
// @Param body body object true "{username, password}"
// @Success 200 {object} object
// @Failure 400 {object} serverutil.Response
// @Router /auth/setup [post]
func setupAuth(c *gin.Context) *serverutil.Response {
	deps, ok := getQueries(c)
	if !ok || (*deps).Database() == nil {
		return serverutil.InternalServerError(nil)
	}

	var req struct {
		Username string `json:"username" binding:"required"`
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}

	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result, err := authutil.Setup(c.Request.Context(), authutil.SetupParams{
		Database: (*deps).Database(),
		Username: req.Username,
		Password: req.Password,
		FilesDir: filesDir,
	})
	if err != nil {
		return serverutil.BadRequest(err)
	}

	setSessionCookie(c, result.SessionToken)
	return serverutil.Ok().WithData(gin.H{
		"token":          result.SessionToken,
		"recoveryPhrase": result.RecoveryPhrase,
		"message":        "Setup complete. Store your recovery phrase somewhere safe — it will not be shown again.",
	})
}

var setupAuthRoute = serverutil.ApiRoute("POST", "/auth/setup", setupAuth)
