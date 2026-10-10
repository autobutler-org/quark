package healthutil_test

import (
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/healthutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/shirou/gopsutil/v4/disk"
)

// #2467: health sized the disk from "/" while the Devices page sized the
// internal device from the filesystem holding the data directory, so the two
// disagreed whenever the data directory was a mount of its own. Run on a
// filesystem this machine really has apart from root.
func TestCurrentHealth_DiskIsTheDataDirFilesystem(t *testing.T) {
	const shm = "/dev/shm"
	root, rootErr := disk.Usage("/")
	want, shmErr := disk.Usage(shm)
	if rootErr != nil || shmErr != nil || root.Total == want.Total {
		t.Skip("no /dev/shm sized apart from /")
	}
	// The data directory follows HOME, and need not exist yet.
	t.Setenv("HOME", filepath.Join(shm, "quark-2467-health-missing"))
	if got := storageutil.DataFilesystemPath(); got != shm {
		t.Skipf("the data directory resolves to %s, not under HOME", got)
	}

	c, err := healthutil.Register()
	if err != nil {
		t.Fatal(err)
	}
	if got := c.CurrentHealth().DiskTotalBytes; got != want.Total {
		t.Errorf("DiskTotalBytes = %d, want %s's %d (/ is %d)", got, shm, want.Total, root.Total)
	}
}
