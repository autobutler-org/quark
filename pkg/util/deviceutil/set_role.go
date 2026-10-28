package deviceutil

import (
	"context"
	"errors"
	"fmt"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// SetRoleParams assigns a role to a storage device. The caller's login
// password is re-entered for this, so the params carry the credentials to check
// as well as the role to write.
type SetRoleParams struct {
	// Ctx bounds the reads and the write.
	Ctx context.Context
	// Queries holds the device_roles rows and the user to authenticate.
	Queries db.Querier
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
	// AcknowledgeHealth lets a Replace soon drive take default storage or the
	// snapshot-backup role. Files already on the drive are left in place.
	// Watch and Unknown do not need it.
	AcknowledgeHealth bool
	// Health, when set, reports a drive's verdict instead of reading SMART.
	// Tests pass a fake. Nil reads through storageutil.
	Health func(storageutil.Device) *storageutil.DiskHealth
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

	// Re-validate the caller's login password.
	if _, _, err := authutil.ValidateBasicAuth(ctx, params.Queries, params.Username, params.Password); err != nil {
		// A raw password goes back as it is: it carries its own 426.
		if errors.Is(err, authutil.ErrAppTooOld) {
			return SetRoleResult{}, err
		}
		return SetRoleResult{}, unauthorized(errors.New("invalid credentials"))
	}

	// For non-unassigned roles, verify the device is actually connected, and
	// that a Replace soon drive is only committed to with an acknowledgment.
	if params.Role != RoleUnassigned {
		statuses, err := params.Storage.GetDeviceStatuses()
		if err != nil {
			return SetRoleResult{}, fmt.Errorf("failed to list devices: %w", err)
		}
		device, found := deviceBySerial(statuses, params.Serial)
		if !found {
			return SetRoleResult{}, invalidf("device with serial %q not found", params.Serial)
		}
		if device.IsInternal && params.Role == "snapshot-backup" {
			return SetRoleResult{}, invalid(errors.New("internal device cannot be assigned as snapshot-backup"))
		}
		stronger := params.Role == "default-storage" && worseDefault(params, statuses, device)
		if err := refuseReplaceSoon(healthFor(params.Ctx, params.Health, device), params.AcknowledgeHealth, stronger); err != nil {
			return SetRoleResult{}, err
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

// worseDefault reports whether device is in worse health than the drive that
// currently holds default storage. A missing role list skips the comparison;
// the Replace soon gate still applies.
func worseDefault(params SetRoleParams, statuses []*storageutil.DeviceStatus, device storageutil.Device) bool {
	roles, err := params.Queries.GetAllDeviceRoles(params.Ctx)
	if err != nil {
		return false
	}
	currentSerial := ""
	haveCurrent := false
	for _, role := range roles {
		if role.Role == "default-storage" {
			currentSerial = role.DeviceSerial
			haveCurrent = true
			break
		}
	}
	if !haveCurrent || currentSerial == deviceSerial(device) {
		return false
	}
	current, found := deviceBySerial(statuses, currentSerial)
	if !found {
		return false
	}
	targetRank := storageutil.HealthRank(verdictOf(healthFor(params.Ctx, params.Health, device)))
	currentRank := storageutil.HealthRank(verdictOf(healthFor(params.Ctx, params.Health, current)))
	return targetRank > currentRank
}
