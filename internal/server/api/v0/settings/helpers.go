package v0_settings

import (
	"github.com/autobutler-org/quark/pkg/util/provisionutil"
	"github.com/autobutler-org/quark/pkg/util/remoteutil"
)

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

// provisionAuthKey is remoteutil.EnsureStarted's provisionFn: a fresh key from
// the provisioning service, in the Quark's own household.
func provisionAuthKey() (string, error) {
	result, err := provisionutil.Enroll()
	return result.AuthKey, err
}
