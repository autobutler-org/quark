package v0_storage_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_storage "github.com/autobutler-org/quark/internal/server/api/v0/storage"
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// newBackupJobEngine serves every storage route over one instance's
// dependency graph. Two engines over one database are two instances. Neither
// runs its queue, so a started backup stays pending.
func newBackupJobEngine(t *testing.T, database *db.DatabaseSqlc) *gin.Engine {
	t.Helper()
	reg := vfs.NewRegistry()
	for _, serial := range []string{"", backupSerial} {
		id := vfs.FilesNamespace(serial)
		if err := reg.Register(vfs.Namespace{ID: id}, vfs.NewMemVFS(id)); err != nil {
			t.Fatal(err)
		}
	}
	queue := jobutil.NewQueue(jobutil.NewQueueParams{Database: database})
	queue.Register(jobutil.RegisterParams{
		Kind:    backup.Kind,
		Handler: backup.NewHandler(backup.NewHandlerParams{Database: database, Registry: reg}),
	})
	deps := deputil.NewDependencies().WithVFSRegistry(reg).WithDatabase(database).WithJobQueue(queue)

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	group := engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_storage.NewRouter())
	serverutil.RegisterRouterWithGroup(group, v0_storage.NewAdminRouter())
	return engine
}

func startBackup(engine *gin.Engine, serial string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v0/storage/devices/snapshot-backup",
		strings.NewReader(`{"targetDeviceSerial":"`+serial+`"}`))
	req.Header.Set("Content-Type", "application/json")
	engine.ServeHTTP(w, req)
	return w
}

func backupStatus(engine *gin.Engine, jobID string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v0/storage/devices/snapshot-backup/status/"+jobID, nil))
	return w
}

// A backup started on one instance holds its target on the other, and the
// other answers its status poll (#3084).
func TestSnapshotBackup_IsOneJobOnEveryInstance(t *testing.T) {
	database := dbtest.NewDB(t)
	if err := database.Queries.UpsertDeviceRole(t.Context(), db.UpsertDeviceRoleParams{
		DeviceSerial: backupSerial,
		Role:         "snapshot-backup",
	}); err != nil {
		t.Fatal(err)
	}
	a, b := newBackupJobEngine(t, database), newBackupJobEngine(t, database)

	w := startBackup(a, backupSerial)
	if w.Code != http.StatusAccepted {
		t.Fatalf("start = %d %s, want 202", w.Code, w.Body.String())
	}
	// The client reads jobId as a string.
	var started struct {
		JobID string `json:"jobId"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &started); err != nil || started.JobID == "" {
		t.Fatalf("start = %s, want a string jobId (%v)", w.Body.String(), err)
	}

	if w := startBackup(b, backupSerial); w.Code != http.StatusConflict || !strings.Contains(w.Body.String(), "job "+started.JobID) {
		t.Errorf("second start on the other instance = %d %s, want 409 naming job %s", w.Code, w.Body.String(), started.JobID)
	}

	w = backupStatus(b, started.JobID)
	if w.Code != http.StatusOK {
		t.Fatalf("status on the other instance = %d %s, want 200", w.Code, w.Body.String())
	}
	var status map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &status); err != nil {
		t.Fatal(err)
	}
	if status["id"] != started.JobID || status["status"] != "PENDING" || status["targetDeviceSerial"] != backupSerial {
		t.Errorf("status = %s", w.Body.String())
	}
	for _, field := range []string{"progress", "totalFiles", "filesCopied", "filesSkipped", "totalBytes", "bytesCopied"} {
		if _, ok := status[field].(float64); !ok {
			t.Errorf("status has no numeric %s: %s", field, w.Body.String())
		}
	}

	for _, jobID := range []string{"999", "no-such-job"} {
		if w := backupStatus(b, jobID); w.Code != http.StatusNotFound {
			t.Errorf("status of %s = %d %s, want 404", jobID, w.Code, w.Body.String())
		}
	}
}

// Built-in storage is the drive with serial "", and it can hold the role.
func TestSnapshotBackup_StartsOnBuiltInStorage(t *testing.T) {
	database := dbtest.NewDB(t)
	if err := database.Queries.UpsertDeviceRole(t.Context(), db.UpsertDeviceRoleParams{
		DeviceSerial: "",
		Role:         "snapshot-backup",
	}); err != nil {
		t.Fatal(err)
	}
	if w := startBackup(newBackupJobEngine(t, database), ""); w.Code != http.StatusAccepted {
		t.Fatalf("start on built-in storage = %d %s, want 202", w.Code, w.Body.String())
	}
}

// sourceSerials names the data drives to copy (#3984). A source that is the
// target or is not attached is a 400 and queues nothing; built-in storage,
// the serial "", is a data drive.
func TestSnapshotBackup_ChecksTheChosenSources(t *testing.T) {
	database := dbtest.NewDB(t)
	if err := database.Queries.UpsertDeviceRole(t.Context(), db.UpsertDeviceRoleParams{
		DeviceSerial: backupSerial,
		Role:         "snapshot-backup",
	}); err != nil {
		t.Fatal(err)
	}
	engine := newBackupJobEngine(t, database)
	post := func(sources string) *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/api/v0/storage/devices/snapshot-backup",
			strings.NewReader(`{"targetDeviceSerial":"`+backupSerial+`","sourceSerials":`+sources+`}`))
		req.Header.Set("Content-Type", "application/json")
		engine.ServeHTTP(w, req)
		return w
	}
	for _, sources := range []string{`["` + backupSerial + `"]`, `["GONE-1"]`, `["", "GONE-1"]`} {
		if w := post(sources); w.Code != http.StatusBadRequest || !strings.Contains(w.Body.String(), "a source must be an attached data drive") {
			t.Errorf("sources %s = %d %s, want 400 naming the rule", sources, w.Code, w.Body.String())
		}
	}
	if w := post(`[""]`); w.Code != http.StatusAccepted {
		t.Fatalf("built-in storage as the source = %d %s, want 202", w.Code, w.Body.String())
	}
}
