package v0_ssh

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/sshutil"
)

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		getSSHStatusRoute,
		setSSHEnabledRoute,
		addSSHKeyRoute,
		removeSSHKeyRoute,
		setSSHPasswordRoute,
		clearSSHPasswordRoute,
	}
}

// sshStatusResponse is whether SSH access can be managed, whether it is on,
// and which keys may sign in as quark.
type sshStatusResponse struct {
	Available bool `json:"available"`
	// Reason is why not, when available is false: unsupported_os,
	// not_service, sshd_missing, helper_missing or no_login_shell.
	Reason  string        `json:"reason,omitempty"`
	Enabled bool          `json:"enabled"`
	Keys    []sshutil.Key `json:"keys"`
}

type setSSHEnabledBody struct {
	Enabled *bool `json:"enabled" binding:"required"`
}

type addSSHKeyBody struct {
	// Key is one public key line, as in id_ed25519.pub.
	Key string `json:"key" binding:"required"`
}

type setSSHPasswordBody struct {
	Password string `json:"password" binding:"required"`
}
