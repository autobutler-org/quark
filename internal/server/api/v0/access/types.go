package v0_access

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		listAccessRoute,
		setAccessRoute,
		revokeAccessRoute,
	}
}

// setAccessBody grants one account or group a level on a path. Exactly one of
// userId and groupId is set.
type setAccessBody struct {
	// DeviceSerial names the device; empty is the internal one.
	DeviceSerial string `json:"deviceSerial"`
	RelPath      string `json:"relPath"`
	UserID       int64  `json:"userId,omitempty"`
	GroupID      int64  `json:"groupId,omitempty"`
	// Level is read, write or owner.
	Level string `json:"level"`
}

// revokeAccessBody removes one account's or group's row on a path. Exactly one
// of userId and groupId is set.
type revokeAccessBody struct {
	// DeviceSerial names the device; empty is the internal one.
	DeviceSerial string `json:"deviceSerial"`
	RelPath      string `json:"relPath"`
	UserID       int64  `json:"userId,omitempty"`
	GroupID      int64  `json:"groupId,omitempty"`
}
