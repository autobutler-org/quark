// cspell:ignore protectionutil

package v0_storage

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/deviceutil"
	"github.com/autobutler-org/quark/pkg/util/protectionutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// deviceError maps what deviceutil reports onto the status codes the client
// contract is written against. The message travels unchanged in every case, so
// the client keeps reading the same sentences it always has.
func deviceError(err error) *serverutil.Response {
	var (
		invalid      *deviceutil.InvalidRequestError
		unauthorized *deviceutil.UnauthorizedError
		notFound     *deviceutil.NotFoundError
		needsAck     *deviceutil.AcknowledgmentRequiredError
	)
	switch {
	case errors.As(err, &needsAck):
		return serverutil.Conflict(err)
	case errors.As(err, &invalid):
		return serverutil.BadRequest(err)
	case errors.As(err, &unauthorized):
		return serverutil.Unauthorized(err)
	case errors.As(err, &notFound):
		return serverutil.NotFound(err)
	}
	return serverutil.InternalServerError(err)
}

// builtInStorageName is what the app calls the internal drive, whatever its
// volume is named.
const builtInStorageName = "Built-in storage"

// protectionStatus loads the roles, the connected devices, the copies each
// backup drive's run folders hold (from its last scan when it is away), and
// the backup drives a snapshot is pending or running onto, and derives the
// protection status.
func protectionStatus(ctx context.Context, deps deputil.Dependencies) (protectionutil.StatusResult, error) {
	queries := deps.Database().Queries
	roles, err := queries.GetAllDeviceRoles(ctx)
	if err != nil {
		return protectionutil.StatusResult{}, fmt.Errorf("list device roles: %w", err)
	}
	names, err := queries.GetAllDeviceNames(ctx)
	if err != nil {
		return protectionutil.StatusResult{}, fmt.Errorf("list device names: %w", err)
	}
	roots, err := deps.StorageService().GetManagedRoots()
	if err != nil {
		return protectionutil.StatusResult{}, fmt.Errorf("list storage devices: %w", err)
	}

	displayNames := make(map[string]string, len(names))
	for _, name := range names {
		displayNames[name.DeviceSerial] = name.DisplayName
	}
	nameOf := func(serial, detected string) string {
		if serial == "" {
			return builtInStorageName
		}
		if name := displayNames[serial]; name != "" {
			return name
		}
		return detected
	}

	params := protectionutil.StatusParams{
		Now:     time.Now(),
		Roles:   make([]protectionutil.Role, 0, len(roles)),
		Devices: make([]protectionutil.Device, 0, len(roots)),
	}
	for _, root := range roots {
		health := storageutil.CachedDriveHealth(ctx, root.DevicePath)
		serial := deviceSerial(root.Device)
		params.Devices = append(params.Devices, protectionutil.Device{
			Serial:      serial,
			Name:        nameOf(serial, root.Name),
			DevicePath:  root.DevicePath,
			ReplaceSoon: health != nil && health.Verdict == storageutil.HealthReplaceSoon,
		})
	}
	for _, role := range roles {
		params.Roles = append(params.Roles, protectionutil.Role{
			Serial: role.DeviceSerial,
			Role:   role.Role,
			Name:   nameOf(role.DeviceSerial, ""),
		})
		if role.Role != "snapshot-backup" {
			continue
		}
		if _, err := queries.GetActiveBackupJob(ctx, role.DeviceSerial); err == nil {
			params.Receiving = append(params.Receiving, role.DeviceSerial)
		} else if !errors.Is(err, sql.ErrNoRows) {
			return protectionutil.StatusResult{}, fmt.Errorf("read active backup: %w", err)
		}
		// Status ignores a copy whose source is not a data drive.
		copies, err := backup.DriveCopies(ctx, queries, deps.VFSRegistry(), role.DeviceSerial)
		if err != nil {
			return protectionutil.StatusResult{}, err
		}
		for _, c := range copies {
			params.Copies = append(params.Copies, protectionutil.Copy{
				BackupSerial: role.DeviceSerial,
				SourceSerial: c.Serial,
				CopiedAt:     c.CompletedAt,
			})
		}
	}
	return protectionutil.Status(params), nil
}

// protectionResponse is the HTTP body for a derived status. The fields match
// protectionutil.StatusResult so the wire format and the swagger model agree.
func protectionResponse(result protectionutil.StatusResult) ProtectionStatus {
	dataDrives := make([]ProtectionDataDrive, 0, len(result.DataDrives))
	for _, drive := range result.DataDrives {
		copies := make([]ProtectionCopy, 0, len(drive.Copies))
		for _, c := range drive.Copies {
			copies = append(copies, ProtectionCopy(c))
		}
		dataDrives = append(dataDrives, ProtectionDataDrive{
			Serial: drive.Serial,
			Name:   drive.Name,
			Level:  string(drive.Level),
			Copies: copies,
		})
	}
	backupDrives := make([]ProtectionBackupDrive, 0, len(result.BackupDrives))
	for _, drive := range result.BackupDrives {
		holds := make([]ProtectionHeldCopy, 0, len(drive.Holds))
		for _, held := range drive.Holds {
			holds = append(holds, ProtectionHeldCopy(held))
		}
		backupDrives = append(backupDrives, ProtectionBackupDrive{
			Serial:     drive.Serial,
			Name:       drive.Name,
			State:      string(drive.State),
			Holds:      holds,
			NewestCopy: drive.NewestCopy,
		})
	}
	return ProtectionStatus{
		Level:        string(result.Level),
		Sentence:     result.Sentence,
		NextStep:     string(result.NextStep),
		DataDrives:   dataDrives,
		BackupDrives: backupDrives,
	}
}

// deviceSerial is the serial a role row is keyed by. The internal drive's is empty.
func deviceSerial(device storageutil.Device) string {
	if device.IsInternal || device.UsbInfo == nil {
		return ""
	}
	return device.UsbInfo.GetSerial()
}
