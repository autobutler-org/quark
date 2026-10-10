//go:build linux

package storageutil

// cspell:ignore Fadvise FADV DONTNEED

import (
	"os"

	"golang.org/x/sys/unix"
)

// evictFromPageCache drops f's cached pages, so the next read of it goes to
// the device. The file must already be synced: dirty pages are kept. Best
// effort, like the probe itself — a filesystem that refuses the advice, or a
// tmpfs whose pages are the file, is read back from memory as before.
func evictFromPageCache(f *os.File) {
	unix.Fadvise(int(f.Fd()), 0, 0, unix.FADV_DONTNEED) //nolint:errcheck // best-effort probe
}
