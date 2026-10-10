package storageutil

import (
	"os"
	"syscall"
	"testing"
)

// FailAtomicRenameForTesting makes every [WriteFileAtomicPerm] rename fail
// with err for one test, standing in for a crash between the flush and the
// rename. The test must not run in parallel.
func FailAtomicRenameForTesting(t *testing.T, err error) {
	t.Helper()
	saved := renameFile
	t.Cleanup(func() { renameFile = saved })
	renameFile = func(string, string) error { return err }
}

// FailAtomicSyncForTesting makes every [WriteFileAtomicPerm] flush of its temp
// fail with err for one test. The test must not run in parallel.
func FailAtomicSyncForTesting(t *testing.T, err error) {
	t.Helper()
	saved := syncFile
	t.Cleanup(func() { syncFile = saved })
	syncFile = func(*os.File) error { return err }
}

// NoHardLinksForTesting makes every hard link fail with EPERM for one test,
// the way exFAT refuses one. The test must not run in parallel.
func NoHardLinksForTesting(t *testing.T) {
	t.Helper()
	saved := linkFile
	t.Cleanup(func() { linkFile = saved })
	linkFile = func(string, string) error { return &os.LinkError{Op: "link", Err: syscall.EPERM} }
}
