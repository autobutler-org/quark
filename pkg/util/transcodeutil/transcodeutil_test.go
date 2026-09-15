package transcodeutil

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
)

const testSerial = "test-serial"

// fakeDetector reports one USB disk mounted at a temp directory, so a serial
// resolves there and nothing falls back to the real system files directory.
type fakeDetector struct {
	mountPoint string
}

func (f *fakeDetector) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Test Disk", MountPoint: f.mountPoint, UsbInfo: fakeUsb{}}}, nil
}

// fakeUsb answers GetSerial, the only method a serial lookup calls. Any other
// call panics on the nil embedded interface, which points straight here.
type fakeUsb struct {
	storageutil.UsbDevice
}

func (fakeUsb) GetSerial() string { return testSerial }

type harness struct {
	storage  *storageutil.StorageService
	filesDir string
	events   <-chan eventbus.Event
	bus      *eventbus.Bus
	// database is nil unless a test checks a job's creator.
	database *db.DatabaseSqlc
}

func newHarness(t *testing.T) harness {
	t.Helper()
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0o755); err != nil {
		t.Fatal(err)
	}
	bus := eventbus.New()
	events, unsub := bus.Subscribe("transcodeutil-test")
	t.Cleanup(unsub)
	return harness{
		storage:  storageutil.NewStorageService(&fakeDetector{mountPoint: mountPoint}),
		filesDir: filesDir,
		events:   events,
		bus:      bus,
	}
}

func (h harness) write(t *testing.T, name string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(h.filesDir, name), []byte("source"), 0o644); err != nil {
		t.Fatal(err)
	}
}

func (h harness) exists(name string) bool {
	_, err := os.Stat(filepath.Join(h.filesDir, name))
	return err == nil
}

// handler builds the transcode Handler around a fake transcode func.
func (h harness) handler(transcode TranscodeFunc) jobutil.Handler {
	return NewHandler(NewHandlerParams{Storage: h.storage, Database: h.database, EventBus: h.bus, Transcode: transcode})
}

// withAccounts gives the harness a database holding bob, who may write the
// videos folder, and returns his id. The source is videos/clip.mov.
func (h *harness) withAccounts(t *testing.T) int64 {
	t.Helper()
	h.database = dbtest.NewDB(t)
	if err := os.MkdirAll(filepath.Join(h.filesDir, "videos"), 0o755); err != nil {
		t.Fatal(err)
	}
	h.write(t, "videos/clip.mov")
	bob := h.createAccount(t, "bob")
	h.grant(t, bob, "videos", accessutil.Write)
	return bob
}

func (h harness) createAccount(t *testing.T, username string) int64 {
	t.Helper()
	user, err := h.database.Queries.CreateUser(context.Background(), db.CreateUserParams{
		Username: username, PasswordHash: "h", RecoveryPhraseHash: "r",
	})
	if err != nil {
		t.Fatal(err)
	}
	return user.ID
}

func (h harness) grant(t *testing.T, userID int64, rel string, level accessutil.Level) {
	t.Helper()
	if err := h.database.Queries.SetUserPathAccess(context.Background(), db.SetUserPathAccessParams{
		DeviceSerial: testSerial,
		RelPath:      rel,
		UserID:       sql.NullInt64{Int64: userID, Valid: true},
		Level:        level.String(),
	}); err != nil {
		t.Fatal(err)
	}
}

// rows lists the access rows as "path=level".
func (h harness) rows(t *testing.T) []string {
	t.Helper()
	list, err := h.database.Db.Query(`SELECT rel_path, level FROM path_access ORDER BY rel_path`)
	if err != nil {
		t.Fatal(err)
	}
	defer list.Close()
	var rows []string
	for list.Next() {
		var rel, level string
		if err := list.Scan(&rel, &level); err != nil {
			t.Fatal(err)
		}
		rows = append(rows, rel+"="+level)
	}
	return rows
}

func TestRunMakesTheCreatorOwnTheOutput(t *testing.T) {
	h := newHarness(t)
	bob := h.withAccounts(t)
	admin := h.createAccount(t, "root")
	if err := h.database.Queries.SetUserAdmin(context.Background(), db.SetUserAdminParams{IsAdmin: 1, Username: "root"}); err != nil {
		t.Fatal(err)
	}

	for _, tc := range []struct {
		name     string
		ctx      context.Context
		want     string
		wantRows []string
	}{
		{"an admin writes no row", jobutil.WithUserID(context.Background(), admin), "videos/clip.mp4", []string{"videos=write"}},
		{"a job with no creator writes no row", context.Background(), "videos/clip_(1).mp4", []string{"videos=write"}},
		{"bob owns what his job wrote", jobutil.WithUserID(context.Background(), bob), "videos/clip_(2).mp4", []string{"videos=write", "videos/clip_(2).mp4=owner"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if err := h.handler(writingTranscode(&[]string{})).Run(tc.ctx, params(t, "videos/clip.mov", "mp4", videoutil.QualitySmall), func(float64) {}); err != nil {
				t.Fatal(err)
			}
			select {
			case e := <-h.events:
				// The row is written before the upload event, so a browser
				// refreshing on it already sees the file as the creator's.
				if e.Path != tc.want || !slices.Equal(h.rows(t), tc.wantRows) {
					t.Errorf("upload of %q with rows %v, want %q with %v", e.Path, h.rows(t), tc.want, tc.wantRows)
				}
			case <-time.After(time.Second):
				t.Fatal("no upload event for the output")
			}
		})
	}
}

func TestRunFailsWhenTheCreatorLosesAccess(t *testing.T) {
	for _, tc := range []struct {
		name string
		// before runs before the job starts, during while ffmpeg runs.
		before, during func(t *testing.T, h harness, bob int64)
		wantErr        error
		wantTranscode  bool
	}{
		{
			name:    "read on the source is gone at the start",
			before:  func(t *testing.T, h harness, bob int64) { h.revoke(t, bob) },
			wantErr: ErrCreatorForbidden,
		},
		{
			name:    "the creator was disabled before the start",
			before:  func(t *testing.T, h harness, _ int64) { h.disable(t, "bob") },
			wantErr: accessutil.ErrCreatorInactive,
		},
		{
			name:          "write on the folder is revoked mid-run",
			during:        func(t *testing.T, h harness, bob int64) { h.grant(t, bob, "videos", accessutil.Read) },
			wantErr:       ErrCreatorForbidden,
			wantTranscode: true,
		},
		{
			name:          "the creator is disabled mid-run",
			during:        func(t *testing.T, h harness, _ int64) { h.disable(t, "bob") },
			wantErr:       accessutil.ErrCreatorInactive,
			wantTranscode: true,
		},
		{
			name: "the creator is deleted mid-run",
			during: func(t *testing.T, h harness, bob int64) {
				if _, err := h.database.Db.Exec(`DELETE FROM users WHERE id = ?`, bob); err != nil {
					t.Fatal(err)
				}
			},
			wantErr:       accessutil.ErrCreatorInactive,
			wantTranscode: true,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			h := newHarness(t)
			bob := h.withAccounts(t)
			if tc.before != nil {
				tc.before(t, h, bob)
			}
			transcoded := false
			transcode := func(_ context.Context, p videoutil.TranscodeParams) error {
				transcoded = true
				if tc.during != nil {
					tc.during(t, h, bob)
				}
				return os.WriteFile(p.Output, []byte("encoded"), 0o644)
			}

			err := h.handler(transcode).Run(jobutil.WithUserID(context.Background(), bob), params(t, "videos/clip.mov", "mp4", videoutil.QualitySmall), func(float64) {})
			if !errors.Is(err, tc.wantErr) {
				t.Fatalf("Run error = %v, want %v", err, tc.wantErr)
			}
			if transcoded != tc.wantTranscode {
				t.Errorf("transcode ran = %v, want %v", transcoded, tc.wantTranscode)
			}
			if h.exists("videos/clip.mp4") {
				t.Error("the output landed")
			}
			if left := entries(t, h.stagingDir()); len(left) != 0 {
				t.Errorf("staging dir holds %v, want it empty", left)
			}
			select {
			case e := <-h.events:
				t.Errorf("published %+v for a job that failed", e)
			default:
			}
		})
	}
}

func (h harness) revoke(t *testing.T, userID int64) {
	t.Helper()
	if _, err := h.database.Queries.DeleteUserPathAccess(context.Background(), db.DeleteUserPathAccessParams{
		UserID:       sql.NullInt64{Int64: userID, Valid: true},
		DeviceSerial: testSerial,
		RelPath:      "videos",
	}); err != nil {
		t.Fatal(err)
	}
}

func (h harness) disable(t *testing.T, username string) {
	t.Helper()
	if _, err := h.database.Queries.SetUserStatus(context.Background(), db.SetUserStatusParams{
		ToStatus: authutil.StatusDisabled, Username: username, FromStatus: authutil.StatusActive,
	}); err != nil {
		t.Fatal(err)
	}
}

func params(t *testing.T, relPath string, format videoutil.Format, quality videoutil.Quality) json.RawMessage {
	t.Helper()
	raw, err := json.Marshal(Params{RelPath: relPath, Serial: testSerial, Format: format, Quality: quality})
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

// writingTranscode writes outPath and reports halfway, the way a successful
// ffmpeg run would. It records every path it was asked to write.
func writingTranscode(paths *[]string) TranscodeFunc {
	return func(_ context.Context, p videoutil.TranscodeParams) error {
		*paths = append(*paths, p.Output)
		p.OnProgress(0.5)
		return os.WriteFile(p.Output, []byte("encoded"), 0o644)
	}
}

func TestRunWritesOutputBesideSourceAndPublishesUpload(t *testing.T) {
	h := newHarness(t)
	h.write(t, "clip.mov")
	var paths []string
	var reported []float64

	err := h.handler(writingTranscode(&paths)).Run(context.Background(), params(t, "clip.mov", "mp4", videoutil.QualitySmall), func(p float64) {
		reported = append(reported, p)
	})
	if err != nil {
		t.Fatal(err)
	}

	if len(paths) != 1 || filepath.Ext(paths[0]) != ".mp4" {
		t.Fatalf("transcoded to %v, want one staged file keeping the extension", paths)
	}
	if len(reported) != 1 || reported[0] != 0.5 {
		t.Errorf("reported progress %v, want the transcode's 0.5 passed through", reported)
	}
	if content, _ := os.ReadFile(filepath.Join(h.filesDir, "clip.mp4")); string(content) != "encoded" {
		t.Error("output was not moved into place")
	}
	if _, err := os.Stat(paths[0]); !errors.Is(err, os.ErrNotExist) {
		t.Error("staged file was left behind")
	}
	select {
	case e := <-h.events:
		if e.Kind != eventbus.EventUpload || e.Path != "clip.mp4" || e.DeviceSerial != testSerial {
			t.Errorf("event = %+v, want an upload of clip.mp4 on %s", e, testSerial)
		}
	case <-time.After(time.Second):
		t.Error("no upload event for the output")
	}
}

// stagingDir is where the harness device's in-progress transcodes belong: its
// data dir's tmp area, beside the files tree rather than in it.
func (h harness) stagingDir() string {
	return filepath.Join(filepath.Dir(h.filesDir), "tmp", "transcode-jobs")
}

// entries lists a directory's names, or nil when it does not exist.
func entries(t *testing.T, dir string) []string {
	t.Helper()
	list, err := os.ReadDir(dir)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		t.Fatal(err)
	}
	names := make([]string, 0, len(list))
	for _, e := range list {
		names = append(names, e.Name())
	}
	return names
}

func TestRunStagesOutputOutsideTheFilesTree(t *testing.T) {
	h := newHarness(t)
	h.write(t, "clip.mov")
	var duringRun []string
	var outDir string
	observing := func(_ context.Context, p videoutil.TranscodeParams) error {
		outPath := p.Output
		if err := os.WriteFile(outPath, []byte("encoded"), 0o644); err != nil {
			return err
		}
		duringRun = entries(t, h.filesDir)
		outDir = filepath.Dir(outPath)
		return nil
	}

	if err := h.handler(observing).Run(context.Background(), params(t, "clip.mov", "mp4", videoutil.QualitySmall), func(float64) {}); err != nil {
		t.Fatal(err)
	}

	if len(duringRun) != 1 || duringRun[0] != "clip.mov" {
		t.Errorf("files dir during the run = %v, want only clip.mov: a partial output must not be listable", duringRun)
	}
	if outDir != h.stagingDir() {
		t.Errorf("transcoded into %s, want the staging dir %s", outDir, h.stagingDir())
	}
	if !h.exists("clip.mp4") {
		t.Error("output was not moved into place")
	}
	if left := entries(t, h.stagingDir()); len(left) != 0 {
		t.Errorf("staging dir holds %v after success, want it empty", left)
	}
}

func TestRunClearsOnlyLeftoversFromAnEarlierProcess(t *testing.T) {
	h := newHarness(t)
	h.write(t, "clip.mov")
	if err := os.MkdirAll(h.stagingDir(), 0o755); err != nil {
		t.Fatal(err)
	}
	stale := filepath.Join(h.stagingDir(), "transcode-123.mp4")
	if err := os.WriteFile(stale, []byte("partial"), 0o644); err != nil {
		t.Fatal(err)
	}
	// Written by a process that has since exited.
	before := processStart.Add(-time.Hour)
	if err := os.Chtimes(stale, before, before); err != nil {
		t.Fatal(err)
	}
	// Another lane's job is writing this one right now.
	live := filepath.Join(h.stagingDir(), "transcode-456.mp4")
	if err := os.WriteFile(live, []byte("in progress"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := h.handler(writingTranscode(&[]string{})).Run(context.Background(), params(t, "clip.mov", "mp4", videoutil.QualitySmall), func(float64) {}); err != nil {
		t.Fatal(err)
	}
	if left := entries(t, h.stagingDir()); len(left) != 1 || left[0] != "transcode-456.mp4" {
		t.Errorf("staging dir holds %v, want the crashed run's leftover gone and the running job's output kept", left)
	}
}

func TestRunNeverOverwritesAndNamesOutputWhenItRuns(t *testing.T) {
	h := newHarness(t)
	h.write(t, "clip.mov")
	h.write(t, "clip.mkv")
	h.write(t, "clip.webm")
	handler := h.handler(writingTranscode(&[]string{}))
	ctx := context.Background()

	// Both jobs share a stem; the second runs after the first wrote clip.mp4.
	for _, name := range []string{"clip.mov", "clip.mkv"} {
		if err := handler.Run(ctx, params(t, name, "mp4", videoutil.QualityOriginal), func(float64) {}); err != nil {
			t.Fatal(err)
		}
	}
	// A small WebM of clip.webm must not replace its own source.
	if err := handler.Run(ctx, params(t, "clip.webm", "webm", videoutil.QualitySmall), func(float64) {}); err != nil {
		t.Fatal(err)
	}

	for _, name := range []string{"clip.mp4", "clip_(1).mp4", "clip_(1).webm"} {
		if !h.exists(name) {
			t.Errorf("%s is missing", name)
		}
	}
	if content, _ := os.ReadFile(filepath.Join(h.filesDir, "clip.webm")); string(content) != "source" {
		t.Error("the small WebM overwrote its source")
	}
}

func TestRunRemovesTempFileOnFailure(t *testing.T) {
	h := newHarness(t)
	h.write(t, "clip.mov")
	failing := func(_ context.Context, p videoutil.TranscodeParams) error {
		outPath := p.Output
		if err := os.WriteFile(outPath, []byte("partial"), 0o644); err != nil {
			return err
		}
		return errors.New("encoder exploded")
	}

	err := h.handler(failing).Run(context.Background(), params(t, "clip.mov", "mp4", videoutil.QualitySmall), func(float64) {})
	if err == nil || err.Error() != "encoder exploded" {
		t.Fatalf("Run error = %v, want the transcode's error", err)
	}
	if h.exists("clip.mp4") || len(entries(t, h.stagingDir())) != 0 {
		t.Error("a failed transcode left a file behind")
	}
}

func TestRunRemovesTempFileOnCancel(t *testing.T) {
	h := newHarness(t)
	h.write(t, "clip.mov")
	started := make(chan struct{})
	blocking := func(ctx context.Context, p videoutil.TranscodeParams) error {
		outPath := p.Output
		if err := os.WriteFile(outPath, []byte("partial"), 0o644); err != nil {
			return err
		}
		close(started)
		<-ctx.Done()
		return ctx.Err()
	}

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- h.handler(blocking).Run(ctx, params(t, "clip.mov", "mp4", videoutil.QualitySmall), func(float64) {})
	}()
	<-started
	cancel()

	if err := <-done; !errors.Is(err, context.Canceled) {
		t.Fatalf("Run error = %v, want context.Canceled", err)
	}
	if h.exists("clip.mp4") || len(entries(t, h.stagingDir())) != 0 {
		t.Error("a canceled transcode left a file behind")
	}
}

func TestRunPicksAFreeNameWhenOneAppearsMidRun(t *testing.T) {
	h := newHarness(t)
	h.write(t, "clip.mov")
	// Someone uploads clip.mp4 while ffmpeg is still encoding.
	racing := func(_ context.Context, p videoutil.TranscodeParams) error {
		outPath := p.Output
		h.write(t, "clip.mp4")
		return os.WriteFile(outPath, []byte("encoded"), 0o644)
	}

	if err := h.handler(racing).Run(context.Background(), params(t, "clip.mov", "mp4", videoutil.QualitySmall), func(float64) {}); err != nil {
		t.Fatal(err)
	}
	if content, _ := os.ReadFile(filepath.Join(h.filesDir, "clip.mp4")); string(content) != "source" {
		t.Error("the transcode replaced a file that appeared mid-run")
	}
	if content, _ := os.ReadFile(filepath.Join(h.filesDir, "clip_(1).mp4")); string(content) != "encoded" {
		t.Error("the output did not land under the next free name")
	}
}

func TestValidate(t *testing.T) {
	h := newHarness(t)
	h.write(t, "clip.mov")
	validate := h.handler(nil).Validate

	cases := []struct {
		name    string
		params  json.RawMessage
		wantErr error
	}{
		{"source still there", params(t, "clip.mov", "mp4", videoutil.QualitySmall), nil},
		{"same format at small quality", params(t, "clip.mov", "mov", videoutil.QualitySmall), nil},
		{"source gone", params(t, "gone.mov", "mp4", videoutil.QualitySmall), ErrSourceNotFound},
		{"path traversal", params(t, "../../../etc/passwd", "mp4", videoutil.QualitySmall), ErrInvalidPath},
		{"unknown format", params(t, "clip.mov", "h264", videoutil.QualitySmall), ErrInvalidFormat},
		{"unknown quality", params(t, "clip.mov", "mp4", "best"), ErrInvalidQuality},
		{"same format at original quality", params(t, "clip.mov", "mov", videoutil.QualityOriginal), ErrInvalidFormat},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if err := validate(c.params); !errors.Is(err, c.wantErr) {
				t.Errorf("Validate error = %v, want %v", err, c.wantErr)
			}
		})
	}
}

func TestJobName(t *testing.T) {
	src := source{relPath: "videos/clip.mkv"}
	if got := jobName(src, Params{Format: "mov", Quality: videoutil.QualityOriginal}); got != "Convert clip.mkv to MOV" {
		t.Errorf("original job name = %q", got)
	}
	if got := jobName(src, Params{Format: "webm", Quality: videoutil.QualitySmall}); got != "Convert clip.mkv to WebM (small)" {
		t.Errorf("small job name = %q", got)
	}
}

func TestEnqueueRejectsBadRequests(t *testing.T) {
	h := newHarness(t)
	queue := jobutil.NewQueue(jobutil.NewQueueParams{Database: dbtest.NewDB(t)})
	queue.Register(jobutil.RegisterParams{Kind: Kind, Handler: h.handler(nil)})
	h.write(t, "notes.txt")

	original := videoutil.QualityOriginal
	cases := []struct {
		name    string
		params  Params
		wantErr error
		// ffmpeg says which formats it writes and whether a file is a video.
		needsFFmpeg bool
	}{
		{"unknown format", Params{RelPath: "clip.mov", Serial: testSerial, Format: "h264", Quality: original}, ErrInvalidFormat, false},
		{"unknown quality", Params{RelPath: "clip.mov", Serial: testSerial, Format: "mp4", Quality: "best"}, ErrInvalidQuality, false},
		{"same format at original quality", Params{RelPath: "clip.MOV", Serial: testSerial, Format: "mov", Quality: original}, ErrInvalidFormat, false},
		{"missing relPath", Params{Serial: testSerial, Format: "mp4", Quality: original}, ErrInvalidPath, false},
		{"path traversal", Params{RelPath: "../../../etc/passwd", Serial: testSerial, Format: "mp4", Quality: original}, ErrInvalidPath, false},
		{"missing source", Params{RelPath: "gone.mov", Serial: testSerial, Format: "mp4", Quality: original}, ErrSourceNotFound, true},
		{"not a video", Params{RelPath: "notes.txt", Serial: testSerial, Format: "mp4", Quality: original}, ErrSourceNotFound, true},
	}
	if available, err := videoutil.AvailableFormats(); err == nil {
		for _, f := range videoutil.Formats() {
			if !slices.Contains(available, f) {
				cases = append(cases, struct {
					name        string
					params      Params
					wantErr     error
					needsFFmpeg bool
				}{"a format this ffmpeg cannot write", Params{RelPath: "notes.txt", Serial: testSerial, Format: f, Quality: original}, ErrInvalidFormat, true})
				break
			}
		}
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if c.needsFFmpeg && !videoutil.Available() {
				t.Skip("ffmpeg not available")
			}
			_, err := Enqueue(context.Background(), EnqueueParams{Queue: queue, Storage: h.storage, Params: c.params})
			if !errors.Is(err, c.wantErr) {
				t.Errorf("Enqueue error = %v, want %v", err, c.wantErr)
			}
		})
	}
	list, err := queue.List(context.Background(), jobutil.ListParams{Kinds: []string{Kind}})
	if err != nil {
		t.Fatal(err)
	}
	if len(list.Jobs) != 0 {
		t.Errorf("rejected requests queued %d job(s)", len(list.Jobs))
	}
}
