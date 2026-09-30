package vaultutil

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log/slog"
	"path/filepath"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
)

// defaultAutoLockSecondsWhenUninitialized is the auto-lock value reported for
// a vault that has no configuration row yet.
const defaultAutoLockSecondsWhenUninitialized = 900

// vaultDBFileName is the vault database's name inside a device's data
// directory.
const vaultDBFileName = "vault.db"

// StatusParams reads the vault's overall state. It spans both databases: the
// vault's own configuration lives on whichever device holds the vault, while
// which device that is lives in the main database.
type StatusParams struct {
	// VaultQueries is the vault database.
	VaultQueries *db.Queries
	// MainQueries is the main database, which records the vault's location.
	MainQueries *db.Queries
	Session     *vaultcrypto.VaultSession
	Storage     *storageutil.StorageService
}

// StatusResult is the vault's state as the caller reports it.
type StatusResult struct {
	Initialized     bool
	Locked          bool
	AutoLockSeconds int64
	StorageDevice   string
	DeviceConnected bool
	LockReason      string
}

// GetLocationParams reads which device the vault is stored on.
type GetLocationParams struct {
	// MainQueries is the main database, which records the vault's location
	// and the user's name for the device.
	MainQueries *db.Queries
	Storage     *storageutil.StorageService
}

// GetLocationResult describes the vault's storage device.
type GetLocationResult struct {
	DeviceSerial    string
	IsExternal      bool
	DeviceConnected bool
	DeviceName      string
}

// SetLocationParams moves the vault to another device, or back to internal
// storage when TargetSerial is empty.
type SetLocationParams struct {
	MainDB  *db.DatabaseSqlc
	VaultDB *db.DatabaseSqlc
	Storage *storageutil.StorageService
	// TargetSerial is the device to move the vault to; "" means internal
	// storage, which is the main database.
	TargetSerial string
}

// SetLocationResult carries the database the vault now lives in, so the caller
// can swap it into the dependency graph. It is nil when the vault moved back
// to internal storage, which needs no separate handle.
type SetLocationResult struct {
	TargetDB *db.DatabaseSqlc
}

// Status reports whether the vault is set up, whether it is unlocked, and
// where it is stored.
func Status(ctx context.Context, params StatusParams) (StatusResult, error) {
	config, err := params.VaultQueries.GetVaultConfig(ctx)

	initialized := true
	autoLock := int64(defaultAutoLockSecondsWhenUninitialized)
	if errors.Is(err, sql.ErrNoRows) {
		initialized = false
	} else if err != nil {
		return StatusResult{}, err
	} else {
		autoLock = config.AutoLockSeconds
	}

	storageDevice := "internal"
	deviceConnected := true
	if serial, locErr := params.MainQueries.GetVaultLocation(ctx); locErr == nil && serial != "" {
		storageDevice = serial
		device, devErr := params.Storage.FindManagedDeviceBySerial(serial)
		deviceConnected = devErr == nil && device != nil
	}

	return StatusResult{
		Initialized:     initialized,
		Locked:          params.Session.IsLocked(),
		AutoLockSeconds: autoLock,
		StorageDevice:   storageDevice,
		DeviceConnected: deviceConnected,
		LockReason:      params.Session.LockReason(),
	}, nil
}

// GetLocation resolves the vault's storage device to something a user can
// recognize: their own name for the device when they have set one, the
// device's reported name otherwise.
func GetLocation(ctx context.Context, params GetLocationParams) (GetLocationResult, error) {
	serial, err := params.MainQueries.GetVaultLocation(ctx)
	if err != nil {
		return GetLocationResult{}, fmt.Errorf("get vault location: %w", err)
	}

	result := GetLocationResult{
		DeviceSerial: serial,
		IsExternal:   serial != "",
	}

	if serial == "" {
		result.DeviceConnected = true
		result.DeviceName = "Internal Storage"
		return result, nil
	}

	device, err := params.Storage.FindManagedDeviceBySerial(serial)
	if err == nil && device != nil {
		result.DeviceConnected = true
		result.DeviceName = device.Name
		if name, err := params.MainQueries.GetDeviceName(ctx, serial); err == nil && name != "" {
			result.DeviceName = name
		}
	}

	return result, nil
}

// SetLocation migrates the vault to another device and points the recorded
// location at it. The steps run in the one order a crash between any two of
// them survives: the copy commits, then the recorded location moves to it, and
// only then is the source emptied. Emptying first left a window where the
// location still named a vault with nothing in it, and a restart there offered
// to set up a new vault over the user's secrets (#2517). A crash before the
// location moves leaves the vault where it was, and a retry replaces the
// partial copy; one after leaves a stale copy on the source, which the next
// move onto that device replaces.
//
// It returns [ErrVaultAlreadyOnDevice] when the target is where the vault
// already lives, and [ErrDeviceNotFound] when the target device is not
// managed or not connected; the caller names the serial in its copy.
func SetLocation(ctx context.Context, params SetLocationParams) (SetLocationResult, error) {
	currentSerial, err := params.MainDB.Queries.GetVaultLocation(ctx)
	if err != nil {
		return SetLocationResult{}, fmt.Errorf("get current vault location: %w", err)
	}

	if currentSerial == params.TargetSerial {
		return SetLocationResult{}, ErrVaultAlreadyOnDevice
	}

	var targetDB *db.DatabaseSqlc
	if params.TargetSerial == "" {
		targetDB = params.MainDB
	} else {
		targetDB, err = openVaultDBForSerial(params.Storage, params.TargetSerial)
		if err != nil {
			return SetLocationResult{}, err
		}
	}

	// A target on another device is a handle this function opened, so it is
	// this function that closes it on every failure below.
	closeTarget := func() {
		if params.TargetSerial != "" {
			targetDB.Db.Close()
		}
	}

	sourceDB := params.VaultDB
	if err := backup.MigrateVault(ctx, sourceDB, targetDB); err != nil {
		closeTarget()
		return SetLocationResult{}, fmt.Errorf("migrate vault: %w", err)
	}

	if err := params.MainDB.Queries.SetVaultLocation(ctx, params.TargetSerial); err != nil {
		closeTarget()
		return SetLocationResult{}, fmt.Errorf("update vault location: %w", err)
	}

	// The vault has moved. A source that cannot be emptied now holds a stale
	// copy, still encrypted under the master password, and failing the move
	// here would leave the caller serving a vault the recorded location no
	// longer names.
	if err := backup.TruncateVaultTables(ctx, sourceDB); err != nil {
		slog.Warn("vault: empty the previous location", "err", err)
	}

	return SetLocationResult{TargetDB: targetDB}, nil
}

// openVaultDBForSerial opens the vault database on a managed device.
func openVaultDBForSerial(storage *storageutil.StorageService, serial string) (*db.DatabaseSqlc, error) {
	device, err := storage.FindManagedDeviceBySerial(serial)
	if err != nil {
		return nil, fmt.Errorf("find device: %w", err)
	}
	if device == nil {
		return nil, ErrDeviceNotFound
	}

	dbPath := filepath.Join(device.DataDir, vaultDBFileName)
	vaultDB, err := db.ConnectToVaultDatabase(dbPath)
	if err != nil {
		return nil, fmt.Errorf("open vault db on device: %w", err)
	}

	return vaultDB, nil
}
