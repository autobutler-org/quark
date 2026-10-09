package v0_notifications

import (
	"errors"
	"time"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/notificationutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/usersettingsutil"
	"github.com/gin-gonic/gin"
)

// listNotifications godoc
// @Summary List your notifications
// @Description Returns the caller's current notifications. The list is derived on each request and not stored, so a notification is there for as long as its condition holds. An admin gets backup_due while this Quark has no completed snapshot backup on record, and backup_stale, with lastBackupAt, once the last one is 30 days old; other accounts get neither. A type listed in the caller's disabledNotifications setting (PUT /settings/me) is left out. link is the app route to open. There is no notification event: refetch on backup_completed, after changing your own settings, and when the app comes back to the foreground.
// @Tags notifications
// @Produce json
// @Success 200 {object} notificationutil.ListResult
// @Failure 401 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /notifications [get]
func listNotifications(c *gin.Context) *serverutil.Response {
	principal, ok := ctxutil.Get[accessutil.Principal](c, "principal")
	if !ok || principal.UserID == 0 {
		return serverutil.Unauthorized(errors.New("authentication required"))
	}
	dataDir := storageutil.GetDataDir()
	settings, err := usersettingsutil.Load(usersettingsutil.LoadParams{DataDir: dataDir, UserID: principal.UserID})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	result, err := notificationutil.List(notificationutil.ListParams{
		DataDir:  dataDir,
		IsAdmin:  principal.IsAdmin,
		Disabled: settings.Settings.DisabledNotifications,
		Now:      time.Now(),
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(result)
}

var listNotificationsRoute = serverutil.ApiRoute("GET", "/notifications", listNotifications)
