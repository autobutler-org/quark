package deviceutil

import (
	"context"
	"errors"
	"fmt"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// SetRoleParams assigns a role to a storage device. The master password is
// re-entered for this, so the params carry the credentials to check as well as
// the role to write.
type SetRoleParams struct {
	// Ctx bounds the reads and the write.
	Ctx context.Context
	// Queries holds the device_roles rows and the user to authenticate.
	Queries *db.Queries
	// Storage lists the connected devices a non-unassigned role needs.
	Storage *storageutil.StorageService
	// Serial identifies the device, empty for the internal one.
	Serial string
	// Role is the role to assign; see [ValidRoles].
	Role string
	// Username and Password re-authenticate the caller.
	Username string
	Password string
	// SessionUsername is the user the request authenticated as, and
	// SessionKnown reports whether the middleware set one. An unknown session
	// skips the match check.
	SessionUsername string
	SessionKnown    bool
}

// SetRoleResult reports the role that was written.
type SetRoleResult struct {
	Serial string
	Role   string
}

// SetRole assigns a role to a device, after checking the credentials and that
// a device meant to hold real data is actually connected.
func SetRole(params SetRoleParams) (SetRoleResult, error) {
	if !ValidRoles[params.Role] {
		return SetRoleResult{}, invalid(errors.New("role must be one of: default-storage, snapshot-backup, unassigned"))
	}

	ctx := params.Ctx

	// Verify username matches the authenticated session.
	if params.SessionKnown && params.SessionUsername != params.Username {
		return SetRoleResult{}, unauthorized(errors.New("username does not match session"))
	}

	// Re-validate master password.
	if _, _, err := authutil.ValidateBasicAuth(ctx, params.Queries, params.Username, params.Password); err != nil {
		return SetRoleResult{}, unauthorized(errors.New("invalid credentials"))
	}

	// For non-unassigned roles, verify the device is actually connected.
	if params.Role != RoleUnassigned {
		statuses, err := params.Storage.GetDeviceStatuses()
		if err != nil {
			return SetRoleResult{}, fmt.Errorf("failed to list devices: %w", err)
		}
		found := false
		isInternal := false
		for _, s := range statuses {
			if params.Serial == "" && s.IsInternal {
				found = true
				isInternal = true
				break
			}
			if s.UsbInfo != nil && s.UsbInfo.GetSerial() == params.Serial {
				found = true
				break
			}
		}
		if !found {
			return SetRoleResult{}, invalidf("device with serial %q not found", params.Serial)
		}
		if isInternal && params.Role == "snapshot-backup" {
			return SetRoleResult{}, invalid(errors.New("internal device cannot be assigned as snapshot-backup"))
		}
	}

	// If assigning default-storage, clear any existing default-storage first.
	if params.Role == "default-storage" {
		if err := params.Queries.ClearDefaultStorageRole(ctx); err != nil {
			return SetRoleResult{}, fmt.Errorf("failed to clear existing default-storage: %w", err)
		}
	}

	if err := params.Queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{
		DeviceSerial: params.Serial,
		Role:         params.Role,
	}); err != nil {
		return SetRoleResult{}, fmt.Errorf("failed to set device role: %w", err)
	}

	return SetRoleResult{Serial: params.Serial, Role: params.Role}, nil
}
