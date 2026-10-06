package backup

import (
	"context"
	"encoding/json"
	"sync"
	"testing"
)

// TestInMemoryBackupJobStore_ReadDuringRun pins that a status read never
// shares memory with the running snapshot. The snapshot goroutine mutates
// its job and calls Update after each file while GET
// /storage/devices/snapshot-backup/status JSON-encodes what Get returns; run
// under -race, the store handed both of them the same pointer.
func TestInMemoryBackupJobStore_ReadDuringRun(t *testing.T) {
	ctx := context.Background()
	store := NewInMemoryBackupJobStore()
	job := &BackupJob{ID: "job", Status: BackupStatusCopying, SourceDevices: make([]SourceDeviceProgress, 1)}
	if err := store.Create(ctx, job); err != nil {
		t.Fatal(err)
	}

	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		for i := 0; i < 200; i++ {
			job.FilesCopied++
			job.SourceDevices[0].FilesCopied++
			_ = store.Update(ctx, job)
		}
	}()
	go func() {
		defer wg.Done()
		for i := 0; i < 200; i++ {
			got, err := store.Get(ctx, "job")
			if err != nil {
				t.Error(err)
				return
			}
			if _, err := json.Marshal(got); err != nil {
				t.Error(err)
				return
			}
		}
	}()
	wg.Wait()

	got, err := store.Get(ctx, "job")
	if err != nil {
		t.Fatal(err)
	}
	if got.FilesCopied != 200 || got.SourceDevices[0].FilesCopied != 200 {
		t.Fatalf("stored job = %d files, %d on the source; want the last update, 200 and 200", got.FilesCopied, got.SourceDevices[0].FilesCopied)
	}
	got.SourceDevices[0].FilesCopied = 0
	if again, _ := store.Get(ctx, "job"); again.SourceDevices[0].FilesCopied != 200 {
		t.Fatal("changing a job Get returned changed the stored job")
	}
}
