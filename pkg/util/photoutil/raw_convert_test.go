package photoutil

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

// TestRawViaDcraw_HungToolReturns pins that a RAW tool that never exits is
// killed when its context ends (#2752). The conversion runs while a request
// holds an IO-semaphore slot, so a hang used to keep that slot forever.
func TestRawViaDcraw_HungToolReturns(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("needs a shell script on PATH")
	}
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, "dcraw"), []byte("#!/bin/sh\nexec sleep 600\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin)

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	done := make(chan error, 1)
	go func() {
		_, err := rawViaDcraw(ctx, filepath.Join(t.TempDir(), "photo.cr2"))
		done <- err
	}()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("a killed dcraw reported success")
		}
	case <-time.After(10 * time.Second):
		t.Fatal("rawViaDcraw still running 10 s after its context ended")
	}
}
