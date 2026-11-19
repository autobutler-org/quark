package albumexportutil_test

import (
	"context"
	"database/sql"
	"encoding/csv"
	"errors"
	"io"
	"path"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/albumexportutil"
	"github.com/autobutler-org/quark/pkg/util/albumutil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// fixture is an account with albums over photos on the internal drive, and an
// empty USB stick to export onto.
type fixture struct {
	database *db.DatabaseSqlc
	queries  db.Querier
	registry vfs.Registry
	queue    *jobutil.Queue
	internal vfs.VFS
	usb      vfs.VFS
	owner    int64
	access   accessutil.Access
}

const usbSerial = "USB-STICK-1"

func newFixture(t *testing.T) fixture {
	t.Helper()
	ctx := context.Background()
	database := dbtest.NewDB(t)
	f := fixture{
		database: database,
		queries:  database.Queries,
		registry: vfs.NewRegistry(),
		queue:    jobutil.NewQueue(jobutil.NewQueueParams{Database: database}),
		internal: vfs.NewMemVFS(vfs.FilesNamespace("")),
		usb:      vfs.NewMemVFS(vfs.FilesNamespace(usbSerial)),
	}
	for serial, fsys := range map[string]vfs.VFS{"": f.internal, usbSerial: f.usb} {
		if err := f.registry.Register(vfs.Namespace{ID: vfs.FilesNamespace(serial)}, fsys); err != nil {
			t.Fatal(err)
		}
	}
	user, err := f.queries.CreateUser(ctx, db.CreateUserParams{Username: "grandma", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	f.queue.Register(jobutil.RegisterParams{Kind: albumexportutil.Kind, Handler: albumexportutil.NewHandler(albumexportutil.NewHandlerParams{
		Database: database, Registry: f.registry,
	})})
	f.owner = user.ID
	loaded, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.Principal{UserID: user.ID, IsAdmin: true}})
	if err != nil {
		t.Fatal(err)
	}
	f.access = loaded.Access
	return f
}

func (f fixture) put(t *testing.T, fsys vfs.VFS, rel, content string) {
	t.Helper()
	ctx := context.Background()
	if err := fsys.MkdirAll(ctx, path.Dir(rel)); err != nil {
		t.Fatal(err)
	}
	if err := fsys.Write(ctx, rel, strings.NewReader(content), vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
}

func (f fixture) album(t *testing.T, name string, parent *db.PhotoAlbum, photos ...string) db.PhotoAlbum {
	t.Helper()
	ctx := context.Background()
	var parentID sql.NullInt64
	if parent != nil {
		parentID = sql.NullInt64{Int64: parent.ID, Valid: true}
	}
	created, err := albumutil.CreateAlbum(ctx, albumutil.CreateAlbumParams{Queries: f.queries, UserID: f.owner, Name: name, ParentID: parentID})
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range photos {
		if _, err := f.queries.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: created.Album.ID, DeviceSerial: "", RelPath: p}); err != nil {
			t.Fatal(err)
		}
	}
	return created.Album
}

func (f fixture) read(t *testing.T, fsys vfs.VFS, rel string) string {
	t.Helper()
	file, err := fsys.Open(context.Background(), rel)
	if err != nil {
		t.Fatalf("open %s: %v", rel, err)
	}
	defer file.Close()
	b, err := io.ReadAll(file)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// manifest reads the export's manifest as one map per row, keyed by header.
func (f fixture) manifest(t *testing.T, folder string) []map[string]string {
	t.Helper()
	records, err := csv.NewReader(strings.NewReader(f.read(t, f.usb, path.Join(folder, albumexportutil.ManifestName)))).ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	var rows []map[string]string
	for _, record := range records[1:] {
		row := map[string]string{}
		for i, h := range records[0] {
			row[h] = record[i]
		}
		rows = append(rows, row)
	}
	return rows
}

func (f fixture) export(t *testing.T, job albumexportutil.JobParams) (albumexportutil.ExportResult, error) {
	t.Helper()
	return albumexportutil.Export(albumexportutil.ExportParams{
		Ctx:      context.Background(),
		Queries:  f.queries,
		Registry: f.registry,
		Access:   f.access,
		Job:      job,
	})
}

func filesUnder(t *testing.T, fsys vfs.VFS, root string) []string {
	t.Helper()
	var files []string
	err := vfs.Walk(context.Background(), fsys, root, func(info vfs.FileInfo) error {
		if !info.IsDir && !strings.Contains(info.Path, "/.") {
			files = append(files, strings.TrimPrefix(info.Path, root+"/"))
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	sort.Strings(files)
	return files
}

// A photo in three albums is copied into each album's folder, and every row
// the manifest has for it names all three albums and its one original.
func TestExport_PhotoInThreeAlbums(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	f.put(t, f.internal, "Camera/beach.jpg", "beach")
	taken := time.Date(2025, 7, 4, 12, 0, 0, 0, time.UTC)
	if err := f.queries.UpsertPhotoHash(ctx, db.UpsertPhotoHashParams{
		DeviceSerial: "", RelPath: "Camera/beach.jpg", TakenAt: sql.NullTime{Time: taken, Valid: true}, TakenChecked: true,
	}); err != nil {
		t.Fatal(err)
	}
	summer := f.album(t, "Summer", nil, "Camera/beach.jpg")
	f.album(t, "Holiday", &summer, "Camera/beach.jpg")
	family := f.album(t, "Family", nil, "Camera/beach.jpg")
	f.put(t, f.usb, "Exports/.keep", "")

	result, err := f.export(t, albumexportutil.JobParams{Serial: usbSerial, RelPath: "Exports/Out", AlbumIDs: []int64{summer.ID, family.ID}})
	if err != nil {
		t.Fatalf("Export: %v", err)
	}
	if result.Copied != 3 || len(result.Failures) != 0 {
		t.Fatalf("result = %+v, want 3 copied and no failures", result)
	}
	want := []string{"Family/beach.jpg", "Summer/Holiday/beach.jpg", "Summer/beach.jpg", albumexportutil.ManifestName}
	if got := filesUnder(t, f.usb, "Exports/Out"); !reflect.DeepEqual(got, want) {
		t.Fatalf("exported files = %v, want %v", got, want)
	}
	if got := f.read(t, f.usb, "Exports/Out/Summer/Holiday/beach.jpg"); got != "beach" {
		t.Fatalf("copy holds %q", got)
	}
	rows := f.manifest(t, "Exports/Out")
	if len(rows) != 3 {
		t.Fatalf("manifest has %d rows, want 3: %v", len(rows), rows)
	}
	for _, row := range rows {
		if row["albums"] != "Family; Summer; Summer/Holiday" {
			t.Errorf("albums = %q, want all three", row["albums"])
		}
		if row["source_drive"] != "Built-in storage" || row["source_path"] != "Camera/beach.jpg" {
			t.Errorf("source = %q %q", row["source_drive"], row["source_path"])
		}
		if row["taken"] != "2025-07-04T12:00:00Z" {
			t.Errorf("taken = %q", row["taken"])
		}
		if row["result"] != "copied" {
			t.Errorf("result = %q", row["result"])
		}
	}

	// The original and the album pointers are untouched.
	if got := f.read(t, f.internal, "Camera/beach.jpg"); got != "beach" {
		t.Fatalf("original now holds %q", got)
	}
	for _, a := range []db.PhotoAlbum{summer, family} {
		items, err := f.queries.ListAlbumItems(ctx, a.ID)
		if err != nil || len(items) != 1 || items[0].RelPath != "Camera/beach.jpg" {
			t.Fatalf("album %s items = %v, %v", a.Name, items, err)
		}
	}
	// The copies are kept out of the photo library.
	if !photoutil.IsDocumentMedia(ctx, f.usb, "Exports/Out/Family/beach.jpg") {
		t.Fatal("export folder is not marked out of the library")
	}
}

// One album exports straight into the export folder.
func TestExport_OneAlbumIsTheFolder(t *testing.T) {
	f := newFixture(t)
	f.put(t, f.internal, "a/IMG_1.jpg", "one")
	f.put(t, f.internal, "b/IMG_1.jpg", "other one")
	holiday := f.album(t, "Holiday", nil, "a/IMG_1.jpg", "b/IMG_1.jpg")
	if _, err := f.export(t, albumexportutil.JobParams{Serial: usbSerial, RelPath: "Holiday", AlbumIDs: []int64{holiday.ID}}); err != nil {
		t.Fatal(err)
	}
	want := []string{"IMG_1 (2).jpg", "IMG_1.jpg", albumexportutil.ManifestName}
	if got := filesUnder(t, f.usb, "Holiday"); !reflect.DeepEqual(got, want) {
		t.Fatalf("exported files = %v, want %v", got, want)
	}
}

// A missing original is listed by name, the rest is still copied, and the
// export reports a partial result rather than success.
func TestExport_FailuresAreListed(t *testing.T) {
	f := newFixture(t)
	f.put(t, f.internal, "Camera/ok.jpg", "ok")
	holiday := f.album(t, "Holiday", nil, "Camera/ok.jpg", "Camera/gone.jpg")

	result, err := f.export(t, albumexportutil.JobParams{Serial: usbSerial, RelPath: "Holiday", AlbumIDs: []int64{holiday.ID}})
	var partial *albumexportutil.PartialError
	if !errors.As(err, &partial) || partial.Failed != 1 || partial.Total != 2 {
		t.Fatalf("err = %v, want a partial export of 1 of 2", err)
	}
	if result.Copied != 1 || len(result.Failures) != 1 || result.Failures[0].Name != "gone.jpg" ||
		result.Failures[0].Reason != albumexportutil.ReasonMissing {
		t.Fatalf("result = %+v", result)
	}

	summary, err := albumexportutil.ReadSummary(albumexportutil.ReadSummaryParams{
		Ctx: context.Background(), Registry: f.registry, Serial: usbSerial, RelPath: "Holiday",
	})
	if err != nil {
		t.Fatal(err)
	}
	if summary.Copied != 1 || len(summary.Failures) != 1 || summary.Failures[0].Name != "gone.jpg" ||
		summary.Failures[0].Path != "gone.jpg" || summary.Failures[0].Reason != albumexportutil.ReasonMissing {
		t.Fatalf("summary = %+v", summary)
	}
}

// The library export takes every album, and puts the photos in none of them
// in a folder of their own, under their original folders.
func TestExport_Library(t *testing.T) {
	f := newFixture(t)
	f.put(t, f.internal, "Camera/in.jpg", "in")
	f.put(t, f.internal, "Camera/loose.jpg", "loose")
	f.album(t, "Holiday", nil, "Camera/in.jpg")
	if _, err := f.export(t, albumexportutil.JobParams{Serial: usbSerial, RelPath: "Library", Library: true}); err != nil {
		t.Fatal(err)
	}
	want := []string{"Holiday/in.jpg", albumexportutil.NotInAlbumFolder + "/Camera/loose.jpg", albumexportutil.ManifestName}
	if got := filesUnder(t, f.usb, "Library"); !reflect.DeepEqual(got, want) {
		t.Fatalf("exported files = %v, want %v", got, want)
	}
}

func TestStartExport(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	holiday := f.album(t, "Holiday", nil)
	f.put(t, f.usb, "Exports/Holiday/old.jpg", "an earlier export")

	start := func(access accessutil.Access, params albumexportutil.StartExportParams) (albumexportutil.StartExportResult, error) {
		params.Ctx, params.Queries, params.Registry, params.Queue, params.Access = ctx, f.queries, f.registry, f.queue, access
		return albumexportutil.StartExport(params)
	}

	result, err := start(f.access, albumexportutil.StartExportParams{AlbumIDs: []int64{holiday.ID}, Serial: usbSerial, Folder: "/Exports"})
	if err != nil {
		t.Fatal(err)
	}
	if result.Serial != usbSerial || result.RelPath != "Exports/Holiday (2)" {
		t.Fatalf("result = %+v, want a new folder beside the earlier export", result)
	}
	got, err := f.queue.Get(ctx, jobutil.GetParams{ID: result.JobID})
	if err != nil {
		t.Fatal(err)
	}
	if got.Job.Kind != albumexportutil.Kind || got.Job.UserID != f.owner {
		t.Fatalf("job = %+v", got.Job)
	}
	if serial, rel := got.Job.Source(); serial != usbSerial || rel != "Exports/Holiday (2)" {
		t.Fatalf("job source = %q %q", serial, rel)
	}

	for name, tc := range map[string]struct {
		params albumexportutil.StartExportParams
		want   error
	}{
		"nothing chosen":    {albumexportutil.StartExportParams{Serial: usbSerial, Folder: "Exports"}, albumexportutil.ErrNothingToExport},
		"another's album":   {albumexportutil.StartExportParams{AlbumIDs: []int64{holiday.ID + 100}, Serial: usbSerial, Folder: "Exports"}, albumexportutil.ErrAlbumNotFound},
		"no such folder":    {albumexportutil.StartExportParams{Library: true, Serial: usbSerial, Folder: "Nope"}, albumexportutil.ErrFolderNotFound},
		"folder is a photo": {albumexportutil.StartExportParams{Library: true, Serial: usbSerial, Folder: "Exports/Holiday/old.jpg"}, albumexportutil.ErrFolderNotFound},
	} {
		if _, err := start(f.access, tc.params); !errors.Is(err, tc.want) {
			t.Errorf("%s: err = %v, want %v", name, err, tc.want)
		}
	}

	// An account with no grant on the stick cannot write an export there.
	denied, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.Principal{UserID: f.owner}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := start(denied.Access, albumexportutil.StartExportParams{Library: true, Serial: usbSerial, Folder: "Exports"}); !errors.Is(err, albumexportutil.ErrDestinationForbidden) {
		t.Fatalf("err = %v, want ErrDestinationForbidden", err)
	}
}
