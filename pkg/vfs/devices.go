package vfs

import (
	"errors"
	"slices"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// filesNamespacePrefix is the internal drive's namespace ID, and the prefix of
// every other device's. See [FilesNamespace].
const filesNamespacePrefix = "files"

// rootSerial is the serial a managed device is addressed by. The internal
// device has no USB descriptor, so it answers to the empty serial.
func rootSerial(d storageutil.ManagedDevice) string {
	if d.UsbInfo == nil {
		return ""
	}
	return d.UsbInfo.GetSerial()
}

// deviceNamespaceSerial reports the serial a device namespace ID names, and
// false for any ID that is not one — the internal drive's "files" included.
func deviceNamespaceSerial(namespaceID string) (string, bool) {
	serial, ok := strings.CutPrefix(namespaceID, filesNamespacePrefix+":")
	return serial, ok && serial != ""
}

func syncDeviceNamespaces(params SyncDeviceNamespacesParams) (SyncDeviceNamespacesResult, error) {
	var result SyncDeviceNamespacesResult
	devices, err := params.Storage.GetManagedRoots()
	if err != nil {
		return result, err
	}

	attached := make(map[string]storageutil.ManagedDevice, len(devices))
	for _, d := range devices {
		if serial := rootSerial(d); serial != "" {
			attached[serial] = d
		}
	}

	for _, ns := range params.Registry.List("") {
		serial, ok := deviceNamespaceSerial(ns.ID)
		if !ok {
			continue
		}
		if _, still := attached[serial]; still {
			delete(attached, serial)
			continue
		}
		params.Registry.Unregister(ns.ID)
		result.Unregistered = append(result.Unregistered, ns.ID)
	}

	// Register in device order so the result reads the way the devices do.
	for _, d := range devices {
		serial := rootSerial(d)
		if _, missing := attached[serial]; !missing {
			continue
		}
		delete(attached, serial)
		id := FilesNamespace(serial)
		err := params.Registry.Register(Namespace{
			ID:          id,
			MountPath:   d.MountPoint,
			Description: "Storage device " + d.Name,
		}, NewDeviceStorageServiceVFS(params.Storage, serial))
		// A concurrent sync got there first; the namespace is what we wanted.
		if err != nil && !errors.Is(err, ErrNamespaceConflict) {
			return result, err
		}
		if err == nil {
			result.Registered = append(result.Registered, id)
		}
	}
	return result, nil
}

// deviceNamespaceIDs is the namespaces ListDevices visits: the internal
// drive's and every device namespace, or only those of the given serials, in
// that order.
func deviceNamespaceIDs(registry Registry, serials []string) []string {
	var ids []string
	if len(serials) > 0 {
		for serial := range serialSet(serials) {
			ids = append(ids, FilesNamespace(serial))
		}
	} else {
		for _, ns := range registry.List("") {
			if _, ok := deviceNamespaceSerial(ns.ID); ok || ns.ID == FilesNamespace("") {
				ids = append(ids, ns.ID)
			}
		}
	}
	// "files" sorts ahead of every "files:<serial>".
	slices.Sort(ids)
	return ids
}

func listDevices(params ListDevicesParams) ([]FileInfo, error) {
	var serials []string
	var perDevice ListFilter
	if params.Filter != nil {
		serials = params.Filter.SerialFilter
		perDevice = *params.Filter
		// Each namespace is one device already.
		perDevice.SerialFilter = nil
	}
	maxResults := perDevice.MaxResults

	out := make([]FileInfo, 0)
	seenDirs := make(map[string]bool)
	sawListing := false
	sawNotFound := false

	for _, id := range deviceNamespaceIDs(params.Registry, serials) {
		if maxResults > 0 && len(out) >= maxResults {
			break
		}
		fsys, ok := params.Registry.Get(id)
		if !ok {
			continue
		}

		filter := perDevice
		if maxResults > 0 {
			filter.MaxResults = maxResults - len(out)
		}
		infos, err := fsys.List(params.Ctx, params.Path, &filter)
		if err != nil {
			if params.Ctx != nil && params.Ctx.Err() != nil {
				return nil, params.Ctx.Err()
			}
			if params.Path != "" {
				sawNotFound = true
			}
			continue
		}
		sawListing = true
		for _, fi := range infos {
			if fi.IsDir {
				if seenDirs[fi.Path] {
					continue
				}
				seenDirs[fi.Path] = true
			}
			out = append(out, fi)
		}
	}

	if params.Path != "" && sawNotFound && !sawListing {
		return nil, ErrNotFound
	}
	return out, nil
}
