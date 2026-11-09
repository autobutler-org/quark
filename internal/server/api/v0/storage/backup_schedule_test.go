package v0_storage_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

func (e runsEngine) getSchedule(query string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	e.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v0/storage/devices/snapshot-backup/schedule"+query, nil))
	return w
}

func (e runsEngine) putSchedule(body string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPut, "/api/v0/storage/devices/snapshot-backup/schedule", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	e.ServeHTTP(w, req)
	return w
}

// withQueue gives the engine a job queue that queues backups and runs none.
func (e runsEngine) withQueue(t *testing.T) runsEngine {
	t.Helper()
	queue := jobutil.NewQueue(jobutil.NewQueueParams{Database: e.database})
	queue.Register(jobutil.RegisterParams{Kind: backup.Kind, Handler: jobutil.Handler{
		Run: func(context.Context, json.RawMessage, func(float64)) error { return nil },
	}})
	e.deps.WithJobQueue(queue)
	return e
}

// A drive with no schedule is off; a weekly one on a drive with a fresh run
// reads back, not due, and publishes backup_schedule_changed.
func TestBackupSchedule_SetAndGet(t *testing.T) {
	e := newRunsEngine(t, twoRunDrive(t)).withQueue(t)
	w := e.getSchedule("?deviceSerial=" + backupSerial)
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"cadence":"off"`) || !strings.Contains(w.Body.String(), `"sourceSerials":[]`) {
		t.Fatalf("get = %d %s, want 200 and off", w.Code, w.Body.String())
	}

	w = e.putSchedule(`{"deviceSerial":"` + backupSerial + `","cadence":"weekly"}`)
	if w.Code != http.StatusOK {
		t.Fatalf("put = %d %s, want 200", w.Code, w.Body.String())
	}
	var got backup.SetScheduleResult
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.Cadence != "weekly" || got.Due || got.JobID != "" || len(got.SourceSerials) != 0 {
		t.Errorf("put = %s, want weekly of every data drive, not due, nothing started", w.Body.String())
	}
	if w := e.getSchedule("?deviceSerial=" + backupSerial); !strings.Contains(w.Body.String(), `"cadence":"weekly"`) {
		t.Errorf("get after put = %s, want weekly", w.Body.String())
	}
	select {
	case evt := <-e.events:
		if evt.Kind != eventbus.EventBackupScheduleChanged {
			t.Errorf("event = %+v, want backup_schedule_changed", evt)
		}
	case <-time.After(time.Second):
		t.Error("no event published")
	}
}

// A schedule that is due on an attached drive starts the backup at once; one
// on a drive that is away is saved and waits for the drive.
func TestBackupSchedule_DueStartsOrWaits(t *testing.T) {
	e := newRunsEngine(t, vfs.NewMemVFS(vfs.FilesNamespace(backupSerial))).withQueue(t)
	w := e.putSchedule(`{"deviceSerial":"` + backupSerial + `","cadence":"daily"}`)
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"jobId":"`) {
		t.Fatalf("put on an attached drive with no run = %d %s, want 200 and a job", w.Code, w.Body.String())
	}
	if _, err := e.database.Queries.GetActiveBackupJob(t.Context(), backupSerial); err != nil {
		t.Errorf("no backup pending onto the drive: %v", err)
	}

	w = e.putSchedule(`{"deviceSerial":"GONE","cadence":"monthly"}`)
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"waitingForDrive":true`) || strings.Contains(w.Body.String(), "jobId") {
		t.Errorf("put on an away drive = %d %s, want 200, waiting for the drive", w.Code, w.Body.String())
	}
}

// An unknown cadence, a drive without the role, a source that is a backup
// drive, and a body that is not JSON are 400.
func TestBackupSchedule_BadRequests(t *testing.T) {
	e := newRunsEngine(t, twoRunDrive(t))
	for _, body := range []string{
		`{"deviceSerial":"` + backupSerial + `","cadence":"hourly"}`,
		`{"deviceSerial":"DATA","cadence":"daily"}`,
		`{"deviceSerial":"` + backupSerial + `","cadence":"daily","sourceSerials":["GONE"]}`,
		`not json`,
	} {
		if w := e.putSchedule(body); w.Code != http.StatusBadRequest {
			t.Errorf("put %s = %d %s, want 400", body, w.Code, w.Body.String())
		}
	}
	if w := e.getSchedule("?deviceSerial=DATA"); w.Code != http.StatusBadRequest {
		t.Errorf("get on a drive without the role = %d %s, want 400", w.Code, w.Body.String())
	}
}
