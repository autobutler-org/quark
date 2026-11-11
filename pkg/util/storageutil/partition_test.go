package storageutil

import (
	"errors"
	"os/exec"
	"testing"

	"golang.org/x/sys/unix"
)

// sizedPartition is a partition with a fixed filesystem type and size.
type sizedPartition struct {
	path   string
	fsType string
	size   int
}

func (p sizedPartition) FsType() string                { return p.fsType }
func (p sizedPartition) MountCommand(string) *exec.Cmd { return nil }
func (p sizedPartition) MountPath() (string, error)    { return "", errors.New("not mounted") }
func (p sizedPartition) Path() string                  { return p.path }
func (p sizedPartition) SizeBytes() (int, error)       { return p.size, nil }
func (p sizedPartition) Stat() (*unix.Statfs_t, error) { return nil, errors.New("not mounted") }

func TestPickPartition(t *testing.T) {
	const mib = 1 << 20
	cases := []struct {
		name       string
		partitions []Partition
		want       string
	}{
		{
			name: "Microsoft reserved then exFAT data (#4017)",
			partitions: []Partition{
				sizedPartition{"/dev/sda1", "", 16 * mib},
				sizedPartition{"/dev/sda2", "exfat", 953_000 * mib},
			},
			want: "/dev/sda2",
		},
		{
			name: "EFI system partition then data",
			partitions: []Partition{
				sizedPartition{"/dev/sda1", "vfat", 200 * mib},
				sizedPartition{"/dev/sda2", "ntfs", 900_000 * mib},
			},
			want: "/dev/sda2",
		},
		{
			name:       "a single partition",
			partitions: []Partition{sizedPartition{"/dev/sda1", "ext4", 32_000 * mib}},
			want:       "/dev/sda1",
		},
		{
			name:       "a whole-disk filesystem",
			partitions: []Partition{sizedPartition{"/dev/sda", "ext4", 64_000 * mib}},
			want:       "/dev/sda",
		},
		{
			name: "equal sizes keep the first",
			partitions: []Partition{
				sizedPartition{"/dev/sda1", "ext4", mib},
				sizedPartition{"/dev/sda2", "ext4", mib},
			},
			want: "/dev/sda1",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := PickPartition(tc.partitions)
			if err != nil {
				t.Fatalf("PickPartition: %v", err)
			}
			if got.Path() != tc.want {
				t.Errorf("PickPartition chose %s, want %s", got.Path(), tc.want)
			}
		})
	}
}

func TestPickPartition_NoFilesystem(t *testing.T) {
	for name, partitions := range map[string][]Partition{
		"no filesystem on any partition": {
			sizedPartition{"/dev/sda1", "", 16 << 20},
			sizedPartition{"/dev/sda2", "", 1 << 30},
		},
		"no partitions": nil,
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := PickPartition(partitions); !errors.Is(err, ErrNoFilesystem) {
				t.Errorf("PickPartition = %v, want ErrNoFilesystem", err)
			}
		})
	}
}
