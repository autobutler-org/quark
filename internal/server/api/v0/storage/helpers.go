// cspell:ignore protectionutil

package v0_storage

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/deviceutil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
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

// protectionStatus loads the roles, devices, and completed snapshot-backup
// jobs and derives the protection level from them.
func protectionStatus(ctx context.Context, deps deputil.Dependencies) (protectionutil.StatusResult, error) {
	roles, err := deps.Database().Queries.GetAllDeviceRoles(ctx)
	if err != nil {
		return protectionutil.StatusResult{}, fmt.Errorf("list device roles: %w", err)
	}
	roots, err := deps.StorageService().GetManagedRoots()
	if err != nil {
		return protectionutil.StatusResult{}, fmt.Errorf("list storage devices: %w", err)
	}
	jobs, err := deps.Database().Queries.ListJobs(ctx, []string{backup.Kind})
	if err != nil {
		return protectionutil.StatusResult{}, fmt.Errorf("list snapshot backups: %w", err)
	}

	params := protectionutil.StatusParams{
		Now:         time.Now(),
		Roles:       make([]protectionutil.Role, 0, len(roles)),
		Devices:     make([]protectionutil.Device, 0, len(roots)),
		Completions: make([]protectionutil.Completion, 0),
	}
	for _, role := range roles {
		params.Roles = append(params.Roles, protectionutil.Role{
			Serial: role.DeviceSerial,
			Role:   role.Role,
		})
		// The drive's own record outlives its pruned job rows; the newest of
		// the two is the one that counts.
		at, err := backup.LastDriveSnapshot(ctx, deps.Database().Queries, role.DeviceSerial)
		if err != nil {
			return protectionutil.StatusResult{}, err
		}
		if !at.IsZero() {
			params.Completions = append(params.Completions, protectionutil.Completion{
				Serial:      role.DeviceSerial,
				CompletedAt: at,
			})
		}
	}
	for _, root := range roots {
		health := storageutil.CachedDriveHealth(ctx, root.DevicePath)
		params.Devices = append(params.Devices, protectionutil.Device{
			Serial:      deviceSerial(root.Device),
			Name:        root.Name,
			DevicePath:  root.DevicePath,
			IsInternal:  root.IsInternal,
			ReplaceSoon: health != nil && health.Verdict == storageutil.HealthReplaceSoon,
		})
	}
	for _, job := range jobs {
		if job.Status != string(jobutil.StatusCompleted) || !job.FinishedAt.Valid {
			continue
		}
		var decoded backup.JobParams
		if err := json.Unmarshal([]byte(job.Params), &decoded); err != nil || decoded.TargetDeviceSerial == "" {
			continue
		}
		params.Completions = append(params.Completions, protectionutil.Completion{
			Serial:      decoded.TargetDeviceSerial,
			CompletedAt: job.FinishedAt.Time,
		})
	}
	return protectionutil.Status(params), nil
}

// protectionResponse is the HTTP body for a derived status. The fields match
// protectionutil.StatusResult so the wire format and the swagger model agree.
func protectionResponse(result protectionutil.StatusResult) ProtectionStatus {
	drives := make([]ProtectionDrive, 0, len(result.Drives))
	for _, drive := range result.Drives {
		drives = append(drives, ProtectionDrive{
			Serial:       drive.Serial,
			Name:         drive.Name,
			Counts:       drive.Counts,
			Reason:       drive.Reason,
			LastBackedUp: drive.LastBackedUp,
		})
	}
	return ProtectionStatus{
		Level:    string(result.Level),
		Sentence: result.Sentence,
		NextStep: string(result.NextStep),
		Drives:   drives,
	}
}

// deviceSerial is the serial a role row is keyed by. The internal drive's is empty.
func deviceSerial(device storageutil.Device) string {
	if device.IsInternal || device.UsbInfo == nil {
		return ""
	}
	return device.UsbInfo.GetSerial()
}
