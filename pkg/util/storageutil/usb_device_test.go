package storageutil

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

// fakeSysBlock lays out sysBlock/<disk>/<child>/partition for each numbered
// child, plus a "queue" directory that is not a partition.
func fakeSysBlock(t *testing.T, disk string, partitions map[string]string) string {
	t.Helper()
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, disk, "queue"), 0o755); err != nil {
		t.Fatal(err)
	}
	for name, number := range partitions {
		dir := filepath.Join(root, disk, name)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, "partition"), []byte(number+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func paths(partitions []Partition) []string {
	out := make([]string, 0, len(partitions))
	for _, p := range partitions {
		out = append(out, p.Path())
	}
	return out
}

// A glob of /dev/sda* sorted sda10 before sda2.
func TestSysfsPartitions_NumericOrder(t *testing.T) {
	root := fakeSysBlock(t, "sda", map[string]string{"sda10": "10", "sda2": "2", "sda1": "1"})
	got, err := sysfsPartitions(root, "sda")
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"/dev/sda1", "/dev/sda2", "/dev/sda10"}; !slices.Equal(paths(got), want) {
		t.Errorf("sysfsPartitions = %v, want %v", paths(got), want)
	}
}

func TestSysfsPartitions_WholeDisk(t *testing.T) {
	root := fakeSysBlock(t, "sdb", nil)
	got, err := sysfsPartitions(root, "sdb")
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"/dev/sdb"}; !slices.Equal(paths(got), want) {
		t.Errorf("sysfsPartitions = %v, want %v", paths(got), want)
	}
}
