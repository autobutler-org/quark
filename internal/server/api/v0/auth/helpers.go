package v0_auth

import (
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// accountRefusalResponse answers a sign-in refused for the account's status
// with 403 and that status, and returns nil for any other error. The status
// field is what the app reads; the error is the sentence to show.
func accountRefusalResponse(err error) *serverutil.Response {
	var status string
	switch {
	case errors.Is(err, authutil.ErrAccountPending):
		status = authutil.StatusPending
	case errors.Is(err, authutil.ErrAccountDisabled):
		status = authutil.StatusDisabled
	default:
		return nil
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusForbidden).WithData(accountRefusal{
		Error:  err.Error(),
		Status: status,
	})
}

const sessionCookieName = "session"
const sessionCookieMaxAge = int(30 * 24 * time.Hour / time.Second)

// isTLS returns true when the underlying connection or a trusted proxy indicates
// that the request arrived over HTTPS. Setting the Secure cookie flag on HTTP
// would prevent the cookie from being sent, so we only set it on TLS connections.
func isTLS(c *gin.Context) bool {
	if c.Request.TLS != nil {
		return true
	}
	// Honor a reverse-proxy header (e.g. an ingress → Quark over plain HTTP),
	// but only from a peer QUARK_TRUSTED_PROXIES trusts.
	return c.Request.Header.Get("X-Forwarded-Proto") == "https" &&
		serverutil.IsTrustedProxy(c.RemoteIP())
}

func setSessionCookie(c *gin.Context, token string) {
	c.SetSameSite(http.SameSiteStrictMode)
	c.SetCookie(sessionCookieName, token, sessionCookieMaxAge, "/", "", isTLS(c), true)
}

func clearSessionCookie(c *gin.Context) {
	c.SetSameSite(http.SameSiteStrictMode)
	c.SetCookie(sessionCookieName, "", -1, "/", "", isTLS(c), true)
}

func getQueries(c *gin.Context) (*deputil.Dependencies, bool) {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	return &deps, ok
}

// externalDeviceDataDirs returns the Quark data directory on each attached
// device that is not the appliance itself.
//
// Only the quark-owned subtree of a drive is returned, never its mount point: a
// factory reset erases what Quark put on a drive, not the rest of the user's
// drive. A device that is not attached is not listed, and so keeps its data.
func externalDeviceDataDirs(deps deputil.Dependencies) ([]string, error) {
	storage := deps.StorageService()
	if storage == nil {
		return nil, nil
	}
	devices, err := storage.GetManagedDevices()
	if err != nil {
		return nil, err
	}

	dataDirs := make([]string, 0, len(devices))
	for _, device := range devices {
		if device.IsInternal {
			continue
		}
		dataDirs = append(dataDirs, device.DataDir)
	}
	return dataDirs, nil
}

// queryBool reads an optional boolean query parameter. An absent parameter is
// false; a present but unparseable one is rejected rather than silently
// defaulting, so a typo on a destructive endpoint cannot read as "no".
func queryBool(c *gin.Context, name string) (bool, bool) {
	raw, present := c.GetQuery(name)
	if !present || raw == "" {
		return false, true
	}
	value, err := strconv.ParseBool(raw)
	if err != nil {
		return false, false
	}
	return value, true
}
