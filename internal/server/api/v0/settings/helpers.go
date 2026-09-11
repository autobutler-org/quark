package v0_settings

import "github.com/autobutler-org/quark/pkg/util/remoteutil"

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
