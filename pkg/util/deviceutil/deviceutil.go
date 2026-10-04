// Package deviceutil holds the services behind /api/v0/storage/devices: the
// mount and unmount of a USB storage device, the display name and role the
// database keeps for each device, and the status list that overlays the two
// onto what the detector reports. It also keeps the connected devices behind
// /api/v0/devices, the HTTP peers that talk to this appliance, bounded.
//
// storageutil owns the hardware — detection, partitions, mount commands — and
// deliberately does not depend on the database. What lives here is the half
// that needs both, plus the validation rules the endpoints apply before
// touching either.
//
// HTTP concerns stay with the caller: [InvalidRequestError],
// [UnauthorizedError] and [NotFoundError] are what a status code is derived
// from, and the messages they carry reach the client unchanged.
package deviceutil

import (
	"errors"
)

// InvalidRequestError reports a request the caller can fix. The handler
// answers it with 400.
type InvalidRequestError struct {
	Err error
}

func (e *InvalidRequestError) Error() string { return e.Err.Error() }

func (e *InvalidRequestError) Unwrap() error { return e.Err }

// UnauthorizedError reports credentials that did not check out. The handler
// answers it with 401.
type UnauthorizedError struct {
	Err error
}

func (e *UnauthorizedError) Error() string { return e.Err.Error() }

func (e *UnauthorizedError) Unwrap() error { return e.Err }

// NotFoundError reports a serial no device answers to. The handler answers it
// with 404.
type NotFoundError struct {
	Err error
}

func (e *NotFoundError) Error() string { return e.Err.Error() }

func (e *NotFoundError) Unwrap() error { return e.Err }

// ErrInvalidDeviceName reports a display name that is blank, longer than
// [MaxDeviceNameLength] runes, or carries control characters. It is answered
// with a bare 400 — the endpoint has never told the client which rule it
// broke, so this error stays inside the service.
var ErrInvalidDeviceName = errors.New("invalid device name")

// ValidRoles are the roles a device may be assigned. The database enforces the
// same set with a CHECK constraint; this map is what rejects a bad one before
// the write is attempted.
var ValidRoles = map[string]bool{
	"default-storage": true,
	"snapshot-backup": true,
	"unassigned":      true,
}

// RoleUnassigned is the role a device reports when the database holds no row
// for it.
const RoleUnassigned = "unassigned"
