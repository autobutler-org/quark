package v0_auth

import (
	"errors"
	"fmt"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/gin-gonic/gin"
)

// deleteAccount godoc
// @Summary Delete account data (factory reset)
// @Description Deletes the selected aspects and logs the caller out everywhere. Pass account=true to delete only the caller's own account, which is what App Store Guideline 5.1.1(v) requires; the other aspects are a factory reset of the appliance. All four are opt-in and a request selecting none is rejected, so a truncated call cannot destroy anything. The JSON body must carry the caller's own password, which is checked before anything is deleted; it travels in the body rather than the URL so it never reaches an access or proxy log. Attempts share the per-IP limit of the sign-in endpoints, so this endpoint cannot be used to guess the password. Databases are dropped and re-migrated in place, so no restart is required. Repeat calls are idempotent while the account exists. External device data is reached only when devices=true; a drive that is not attached at reset time keeps its data. Deleting the last account returns the appliance to first-boot setup by design. Aspects are independent: deleting the account or the database does NOT delete stored files, and files left behind are readable by whoever sets the appliance up next — the response reports filesRetained=true whenever that happens, so pass files=true as well to erase the data itself.
// @Tags auth
// @Accept json
// @Produce json
// @Param account query bool false "Delete the caller's own account (users row). Does NOT delete stored files unless files=true is also passed; files left behind stay readable by whoever sets the appliance up next."
// @Param database query bool false "Delete the appliance databases (quark.db, quark.health.db). Does NOT delete stored files unless files=true is also passed; files left behind stay readable by whoever sets the appliance up next."
// @Param files query bool false "Delete stored files under the data directory"
// @Param devices query bool false "Delete the Quark data directory on attached external devices"
// @Param body body deleteAccountBody true "The caller's own password"
// @Success 200 {object} object{deleted=object{account=bool,database=bool,files=bool,devices=bool},filesRetained=bool}
// @Failure 400 {object} serverutil.Response
// @Failure 401 {object} serverutil.Response "no session, or the session's account no longer exists"
// @Failure 403 {object} serverutil.Response "the password is wrong, or database, files or devices were requested by a non-admin"
// @Failure 409 {object} serverutil.Response "account=true from the only active admin while other active or disabled accounts exist; nothing is deleted"
// @Failure 429 {object} serverutil.Response "too many attempts from this address; nothing is deleted"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /auth/account [delete]
func deleteAccount(c *gin.Context) *serverutil.Response {
	deps, ok := getQueries(c)
	if !ok || (*deps).Database() == nil {
		return serverutil.InternalServerError(fmt.Errorf("dependencies not found in context"))
	}

	// The username is what this handler needs: the password is checked against
	// it, and the user record is looked up from it below.
	username, ok := ctxutil.Get[string](c, "username")
	if !ok || username == "" {
		return serverutil.Unauthorized(fmt.Errorf("not authenticated"))
	}

	deleteAccount, ok := queryBool(c, "account")
	if !ok {
		return serverutil.BadRequest(fmt.Errorf("account must be a boolean"))
	}
	deleteDatabase, ok := queryBool(c, "database")
	if !ok {
		return serverutil.BadRequest(fmt.Errorf("database must be a boolean"))
	}
	deleteFiles, ok := queryBool(c, "files")
	if !ok {
		return serverutil.BadRequest(fmt.Errorf("files must be a boolean"))
	}
	deleteDevices, ok := queryBool(c, "devices")
	if !ok {
		return serverutil.BadRequest(fmt.Errorf("devices must be a boolean"))
	}
	if !deleteAccount && !deleteDatabase && !deleteFiles && !deleteDevices {
		return serverutil.BadRequest(fmt.Errorf("nothing selected: pass account=true, database=true, files=true, devices=true, or any combination"))
	}
	// Deleting your own account is self-service. The other aspects reset the
	// whole appliance for every account on it, so they need an admin.
	if deleteDatabase || deleteFiles || deleteDevices {
		isAdmin, err := authutil.IsAdmin(c.Request.Context(), (*deps).Database().Queries, username)
		if err != nil {
			return serverutil.InternalServerError(err)
		}
		if !isAdmin {
			return serverutil.NewResponse().WithStatusCode(http.StatusForbidden).WithError(errors.New("admin access required"))
		}
	}
	// Every attempt spends from the sign-in limiter before the password is
	// looked at, so this endpoint is no faster a way to guess it than login.
	if !(*deps).AuthRateLimiter().Allow(ratelimitutil.ExtractIP(c.ClientIP())) {
		return serverutil.NewResponse().WithStatusCode(http.StatusTooManyRequests).WithError(errors.New("too many requests, please slow down"))
	}
	var body deleteAccountBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(fmt.Errorf("password is required"))
	}
	_, err := authutil.VerifyPassword(c.Request.Context(), authutil.VerifyPasswordParams{
		Queries:  (*deps).Database().Queries,
		Username: username,
		Password: body.Password,
	})
	if errors.Is(err, authutil.ErrIncorrectPassword) {
		return serverutil.NewResponse().WithStatusCode(http.StatusForbidden).WithError(err)
	}
	// A session that outlived its account has no password left to prove, and
	// nothing it could still act on.
	if errors.Is(err, authutil.ErrUserNotFound) {
		return serverutil.Unauthorized(fmt.Errorf("not authenticated"))
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	database := (*deps).Database()
	user, err := database.Queries.GetUserByUsername(c.Request.Context(), username)
	if err != nil {
		return serverutil.InternalServerError(fmt.Errorf("failed to resolve authenticated user: %w", err))
	}

	// Resolved only when devices are actually in scope: listing managed devices
	// probes the attached drives, and nothing should touch them otherwise.
	var deviceDataDirs []string
	if deleteDevices {
		deviceDataDirs, err = externalDeviceDataDirs(*deps)
		if err != nil {
			return serverutil.InternalServerError(fmt.Errorf("failed to list external devices: %w", err))
		}
		// An off-appliance vault lives inside one of those directories, so its
		// handle has to be closed before the directory goes or the process
		// keeps writing to an unlinked file.
		(*deps).ClearVaultDB()
	}

	result, err := authutil.DeleteAccount(c.Request.Context(), authutil.DeleteAccountParams{
		Database:       database,
		Queries:        database.Queries,
		HealthDatabase: (*deps).HealthDatabase(),
		DataDir:        storageutil.GetDataDir(),
		DeviceDataDirs: deviceDataDirs,
		Username:       username,
		UserID:         user.ID,
		DeleteAccount:  deleteAccount,
		DeleteDatabase: deleteDatabase,
		DeleteFiles:    deleteFiles,
		DeleteDevices:  deleteDevices,
	})
	if errors.Is(err, authutil.ErrLastAdmin) {
		return serverutil.Conflict(err)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if bus := (*deps).EventBus(); bus != nil && result.AccountDeleted {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
	}

	clearSessionCookie(c)
	return serverutil.Ok().WithData(gin.H{
		"deleted": gin.H{
			"account":  result.AccountDeleted,
			"database": result.DatabaseDeleted,
			"files":    result.FilesDeleted,
			"devices":  result.DevicesDeleted,
		},
		// The client could derive this from the params it sent, but the rule is
		// a security notice rather than arithmetic: stating it server-side means
		// one place decides what counts as data left behind, and a client keys a
		// warning off the flag instead of re-deriving it and getting it wrong.
		"filesRetained": result.FilesRetained,
	})
}

var deleteAccountRoute = serverutil.ApiRoute("DELETE", "/auth/account", deleteAccount)
