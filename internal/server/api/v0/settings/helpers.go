package v0_settings

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/provisionutil"
	"github.com/autobutler-org/quark/pkg/util/remoteutil"
	"github.com/gin-gonic/gin"
)

// callerID returns the signed-in user's id. It is the only id the /settings/me
// routes act on, so one account cannot reach another's settings.
func callerID(c *gin.Context) (int64, error) {
	userID, ok := ctxutil.Get[int64](c, "userID")
	if !ok || userID == 0 {
		return 0, errors.New("authentication required")
	}
	return userID, nil
}

// remoteAccessResponse pairs the persisted on/off setting with what the tsnet
// node is actually doing, so "on, but not connected" is visible (#1815).
func remoteAccessResponse(enabled bool) RemoteAccessResponse {
	status := remoteutil.Status()
	return RemoteAccessResponse{
		Enabled:   enabled,
		Connected: status.Connected,
		RemoteURL: status.RemoteURL,
		Error:     status.Error,
	}
}

// provisionAuthKey is remoteutil.Enable's provisionFn: a fresh key from
// the provisioning service, in the Quark's own household.
func provisionAuthKey() (string, error) {
	result, err := provisionutil.Enroll()
	return result.AuthKey, err
}
