package v0_auth

import (
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"

	"github.com/gin-gonic/gin"
)

// setupAuth godoc
// @Summary First-boot user setup
// @Description Creates the owner account, with a home under users/ on the internal device that it owns; an existing folder of that name under users/ becomes the home. Can only be called once. The body carries authKey, the standard base64 of the 32-byte key the client derived from the password and the salt GET /auth/salt returned, and recoveryKey, the standard base64 of the 32-byte key the client derived from a recovery phrase it generated and the same salt; the Quark makes no phrase. Without recoveryKey the account cannot recover until a sign-in gives it one. A body carrying password, the raw password an app from before auth keys sends, is refused with 426 before anything is checked (#2430). The response carries token.
// @Tags auth
// @Accept json
// @Produce json
// @Param body body newAccountBody true "The username, the authKey and the recoveryKey"
// @Success 200 {object} object
// @Failure 400 {object} serverutil.Response
// @Failure 426 {object} serverutil.Response "the body carried a raw password or phrase: the app is too old"
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
	if err := authutil.RefuseRawSecrets(req.Password); err != nil {
		return serverutil.UpgradeRequired(err)
	}

	files, err := authutil.InternalFiles((*deps).VFSRegistry())
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result, err := authutil.Setup(c.Request.Context(), authutil.SetupParams{
		Database:    (*deps).Database(),
		Username:    req.Username,
		AuthKey:     req.AuthKey,
		RecoveryKey: req.RecoveryKey,
		SaltSecret:  settingsutil.AuthSaltSecret,
		Files:       files,
	})
	if err != nil {
		return serverutil.BadRequest(err)
	}

	setSessionCookie(c, result.SessionToken)
	return serverutil.Ok().WithData(gin.H{"token": result.SessionToken, "message": "Setup complete."})
}

var setupAuthRoute = serverutil.ApiRoute("POST", "/auth/setup", setupAuth)
