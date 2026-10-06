package storageutil

import (
	"os"
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
