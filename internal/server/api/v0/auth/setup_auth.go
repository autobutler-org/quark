package v0_auth

import (
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/gin-gonic/gin"
)

// setupAuth godoc
// @Summary First-boot user setup
// @Description Creates the owner account, with a home under users/ on the internal device that it owns; an existing folder of that name under users/ becomes the home. Can only be called once. The body carries exactly one of password and authKey, the standard base64 of the 32-byte key the client derived from the password and the salt GET /auth/salt returned. The response carries token and, unless the body carried recoveryKey, recoveryPhrase, shown this once. recoveryKey, sent only with authKey, is the standard base64 of the 32-byte key the client derived from a recovery phrase it generated and the same salt: the Quark stores that key and makes no phrase (#2430).
// @Tags auth
// @Accept json
// @Produce json
// @Param body body newAccountBody true "The username with a password or an authKey, and optionally a recoveryKey"
// @Success 200 {object} object
// @Failure 400 {object} serverutil.Response
// @Router /auth/setup [post]
func setupAuth(c *gin.Context) *serverutil.Response {
	deps, ok := getQueries(c)
	if !ok || (*deps).Database() == nil {
		return serverutil.InternalServerError(nil)
	}

	var req newAccountBody
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}

	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result, err := authutil.Setup(c.Request.Context(), authutil.SetupParams{
		Database:    (*deps).Database(),
		Username:    req.Username,
		Password:    req.Password,
		AuthKey:     req.AuthKey,
		RecoveryKey: req.RecoveryKey,
		SaltSecret:  settingsutil.AuthSaltSecret,
		FilesDir:    filesDir,
	})
	if err != nil {
		return serverutil.BadRequest(err)
	}

	setSessionCookie(c, result.SessionToken)
	response := gin.H{"token": result.SessionToken, "message": "Setup complete."}
	if result.RecoveryPhrase != "" {
		response["recoveryPhrase"] = result.RecoveryPhrase
		response["message"] = "Setup complete. Store your recovery phrase somewhere safe — it will not be shown again."
	}
	return serverutil.Ok().WithData(response)
}

var setupAuthRoute = serverutil.ApiRoute("POST", "/auth/setup", setupAuth)
