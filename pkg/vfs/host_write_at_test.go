package vfs

import (
	"os"
	"path/filepath"
	"testing"
)

func TestHostWriteAt_OverwritesInPlaceAndNeverGrows(t *testing.T) {
	p := filepath.Join(t.TempDir(), "a.bin")
	if err := os.WriteFile(p, []byte("abcdef"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := hostWriteAt(p, []byte("XY"), 2); err != nil {
		t.Fatalf("hostWriteAt: %v", err)
	}
	if got, _ := os.ReadFile(p); string(got) != "abXYef" {
		t.Errorf("got %q, want abXYef", got)
	}
	if err := hostWriteAt(p, []byte("XY"), 5); err == nil {
		t.Error("a write past the end succeeded; want an error")
	}
	if err := hostWriteAt(filepath.Join(filepath.Dir(p), "missing"), []byte("X"), 0); err == nil {
		t.Error("a write to a missing file succeeded; want ErrNotFound")
	}
}
