package v0_admin

import (
	"errors"
	"net/http"
	"time"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"

	"github.com/gin-gonic/gin"
)

// createUser godoc
// @Summary Add an account
// @Description Creates an active account with authKey: the standard base64 of the 32-byte key the admin's client derived from the password and the salt GET /auth/salt returned for the new username. A body carrying password, the raw password an app from before auth keys sends, is refused with 426 before anything is checked (#2430). The admin never sees a recovery phrase: the account's client gives it one on its first sign-in. The account's home is made under users/ on the internal device, named after the account, and the account owns it. An existing folder of that name under users/ becomes the home, and a top-level folder of that name does not collide. Admin-only.
// @Tags admin
// @Accept json
// @Produce json
// @Param body body createUserBody true "The account to add"
// @Success 201 {object} userSummary
// @Failure 400 {object} serverutil.Response "invalid username or authKey"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 409 {object} serverutil.Response "that username is taken"
// @Failure 426 {object} serverutil.Response "the body carried a raw password: the app is too old"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /admin/users [post]
func createUser(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	database := deps.Database()
	if database == nil {
		return serverutil.InternalServerError(errors.New("database unavailable"))
	}

	var req createUserBody
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}
	if err := authutil.RefuseRawSecrets(req.Password); err != nil {
		return serverutil.UpgradeRequired(err)
	}
	files, err := authutil.InternalFiles(deps.VFSRegistry())
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result, err := authutil.CreateUser(c.Request.Context(), authutil.CreateUserParams{
		Database:   database,
		Username:   req.Username,
		AuthKey:    req.AuthKey,
		SaltSecret: settingsutil.AuthSaltSecret,
		Files:      files,
	})
	if err != nil {
		return accountErrorResponse(err)
	}

	if bus := deps.EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
		bus.Publish(eventbus.Event{Kind: eventbus.EventNewFolder, Path: result.FolderPath})
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusCreated).WithData(userSummary{
		ID:        result.UserID,
		Username:  req.Username,
		Status:    authutil.StatusActive,
		CreatedAt: result.CreatedAt.Format(time.RFC3339),
	})
}

var createUserRoute = serverutil.ApiRoute("POST", "/admin/users", createUser)
