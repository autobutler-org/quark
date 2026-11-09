package backup

import (
	"fmt"
	"slices"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// maxNamedSources is how many source drives a backup's job name lists before
// it counts the rest.
const maxNamedSources = 2

// driveNames maps each managed device's serial to what the app calls it.
// Built-in storage is "". A nil storage service, or one that cannot list its
// devices, names nothing, and [driveName] falls back.
func driveNames(storage *storageutil.StorageService) map[string]string {
	names := map[string]string{}
	if storage == nil {
		return names
	}
	managed, err := storage.GetManagedDevices()
	if err != nil {
		return names
	}
	for _, d := range managed {
		serial := ""
		if d.UsbInfo != nil {
			serial = d.UsbInfo.GetSerial()
		}
		names[serial] = d.Name
	}
	return names
}

// driveName is "Built-in storage" for serial "", what names calls any other
// serial, or a name built from the serial when it has none.
func driveName(names map[string]string, serial string) string {
	switch {
	case serial == "":
		// The app calls it this whatever its volume is named.
		return "Built-in storage"
	case names[serial] != "":
		return names[serial]
	default:
		return "drive " + serial[:min(len(serial), 8)]
	}
}

// sourceName is what the app calls a source drive.
func sourceName(src SourceDevice) string {
	return driveName(map[string]string{src.Serial: src.Name}, src.Serial)
}

// backupJobName names a backup after the drives it copies and the drive it
// copies them onto: "Back up Quark, Photos and 1 more onto Built-in storage".
// The target and the other backup drives are not copied.
func backupJobName(names map[string]string, backups map[string]bool, target string) string {
	sources := make([]string, 0, len(names))
	for serial := range names {
		if serial != target && !backups[serial] {
			sources = append(sources, driveName(names, serial))
		}
	}
	slices.Sort(sources)
	onto := driveName(names, target)
	switch {
	case len(sources) == 0:
		return "Back up onto " + onto
	case len(sources) > maxNamedSources:
		return fmt.Sprintf("Back up %s and %d more onto %s",
			strings.Join(sources[:maxNamedSources], ", "), len(sources)-maxNamedSources, onto)
	default:
		return fmt.Sprintf("Back up %s onto %s", strings.Join(sources, ", "), onto)
	}
}

// restoreJobName names a restore after the snapshot drive it copies from.
func restoreJobName(names map[string]string, backupSerial string) string {
	return "Restore files from " + driveName(names, backupSerial)
}
