package v0_auth

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"

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

func passwordRefusal(err error) *serverutil.Response {
	switch {
	case errors.Is(err, authutil.ErrIncorrectPassword):
		return serverutil.NewResponse().WithStatusCode(http.StatusForbidden).WithError(err)
	case errors.Is(err, authutil.ErrUserNotFound):
		return serverutil.Unauthorized(errors.New("not authenticated"))
	default:
		return nil
	}
}

// storeRewrappedKeys validates the chat keys and vault key a credential change
// carries, and returns the step that stores them inside that change's
// transaction, nil when the body carried neither, and the announcement to make
// once the change has committed. Recovery, a recovery-key rotation and a
// password change all hand the account's chat identity and vault key back
// re-wrapped (#2416, #2430, #3022, #3459).
func storeRewrappedKeys(ctx context.Context, deps deputil.Dependencies, chatKeys *chatutil.Keys, vaultKey *vaultutil.Key) (func(db.Querier, int64) error, func(), error) {
	if chatKeys != nil {
		if err := chatutil.ValidateKeys(*chatKeys); err != nil {
			return nil, nil, err
		}
	}
	if vaultKey != nil {
		if err := vaultutil.ValidateKey(*vaultKey); err != nil {
			return nil, nil, err
		}
	}
	if chatKeys == nil && vaultKey == nil {
		return nil, func() {}, nil
	}
	// The step learns whose keys these are, which a recovery only knows once
	// it has checked the recovery key.
	var owner int64
	store := func(q db.Querier, userID int64) error {
		owner = userID
		if chatKeys != nil {
			if _, err := chatutil.PutKeys(chatutil.PutKeysParams{Ctx: ctx, Queries: q, UserID: userID, Keys: *chatKeys}); err != nil {
				return err
			}
		}
		if vaultKey != nil {
			if _, err := vaultutil.PutKey(vaultutil.PutKeyParams{Ctx: ctx, Queries: q, UserID: userID, Key: *vaultKey}); err != nil {
				return err
			}
		}
		return nil
	}
	announce := func() {
		// New chat keys ask channel members to refill key grants, as
		// PUT /chat/keys/me does. Best-effort: clients also check when they
		// open a channel.
		if chatKeys != nil {
			if _, err := chatutil.NotifyKeyNeeded(chatutil.NotifyKeyNeededParams{
				Ctx: ctx, Database: deps.Database(), EventBus: deps.EventBus(),
			}); err != nil {
				log.Printf("[auth] chat key needs after new keys: %v", err)
			}
		}
		if vaultKey != nil {
			vaultutil.PublishChanged(vaultutil.PublishChangedParams{EventBus: deps.EventBus(), UserID: owner})
		}
	}
	return store, announce, nil
}

// lockoutResponse answers a sign-in the login guard refused with 429 and
// Retry-After in whole seconds, rounded up so a client that waits exactly that
// long is let in, and returns nil for any other error.
func lockoutResponse(c *gin.Context, err error) *serverutil.Response {
	var locked *authutil.TooManyAttemptsError
	if !errors.As(err, &locked) {
		return nil
	}
	c.Header("Retry-After", strconv.Itoa(int((locked.RetryAfter+time.Second-1)/time.Second)))
	return serverutil.NewResponse().WithStatusCode(http.StatusTooManyRequests).WithError(err)
}

const sessionCookieName = "session"

// The cookie outlives a session that is never renewed, which costs nothing:
// the Quark decides when a session ends, and the cookie only has to last as
// long as the longest one can (#2156).
const sessionCookieMaxAge = int(authutil.SessionMaxLifetime / time.Second)

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

// errRecoveryKeyChanged refuses a body whose currentRecoveryKey and
// recoveryKey differ: re-confirming with the current phrase keeps it, and a
// new phrase is given with password instead (#3530).
var errRecoveryKeyChanged = errors.New("currentRecoveryKey keeps the recovery phrase, so recoveryKey must be the same key")

// confirmRecoveryKey answers PUT /auth/recovery-key for a body carrying
// currentRecoveryKey: it stores the keys wrapped under the phrase the account
// already has, once the Quark has checked that key, and never replaces it
// (#3530).
func confirmRecoveryKey(c *gin.Context, deps deputil.Dependencies, userID int64, req setRecoveryKeyBody) *serverutil.Response {
	if req.RecoveryKey != req.CurrentRecoveryKey {
		return serverutil.BadRequest(errRecoveryKeyChanged)
	}
	afterConfirm, announce, err := storeRewrappedKeys(c.Request.Context(), deps, req.ChatKeys, req.VaultKey)
	if err != nil {
		return serverutil.BadRequest(err)
	}
	_, err = authutil.ConfirmRecoveryKey(c.Request.Context(), deps.Database(), authutil.ConfirmRecoveryKeyParams{
		UserID:       userID,
		RecoveryKey:  req.CurrentRecoveryKey,
		Guard:        deps.LoginGuard(),
		ClientIP:     ratelimitutil.ExtractIP(c.ClientIP()),
		AfterConfirm: afterConfirm,
	})
	if locked := lockoutResponse(c, err); locked != nil {
		return locked
	}
	switch {
	case errors.Is(err, authutil.ErrInvalidRecoveryKey):
		return serverutil.BadRequest(err)
	case errors.Is(err, authutil.ErrInvalidRecoveryPhrase):
		return serverutil.NewResponse().WithStatusCode(http.StatusForbidden).WithError(err)
	case errors.Is(err, authutil.ErrUserNotFound):
		return serverutil.Unauthorized(fmt.Errorf("not authenticated"))
	case err != nil:
		return serverutil.InternalServerError(err)
	}
	announce()
	return serverutil.NewResponse().WithStatusCode(http.StatusNoContent)
}
