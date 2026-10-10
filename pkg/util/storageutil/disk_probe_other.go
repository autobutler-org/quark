//go:build !linux

package storageutil

import "os"

// evictFromPageCache does nothing off Linux, so a probe there still reads its
// file back from memory. Quark ships on Linux; macOS is a development host.
func evictFromPageCache(*os.File) {}
