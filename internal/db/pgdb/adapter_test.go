package pgdb_test

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
)

// The same calls give the same answers on both engines. exerciseQuerier holds
// only a db.Querier, as every caller does; this runs it on SQLite, where it
// is the reference, and TestAdapterOnPostgres runs it through the adapter.
func TestQuerierOnSQLite(t *testing.T) {
	database := dbtest.NewDB(t)
	exerciseQuerier(t, database.Db)
}

func TestAdapterOnPostgres(t *testing.T) {
	conn := openPostgres(t)
	exerciseQuerier(t, conn)

	// GetActiveBackupJob's predicate has to be the expression
	// idx_jobs_backup_target indexes, json_extract() included, or the planner
	// cannot use the index.
	tx, err := conn.Begin()
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`SET LOCAL enable_seqscan = off`); err != nil {
		t.Fatal(err)
	}
	rows, err := tx.Query(`EXPLAIN SELECT id FROM jobs WHERE kind = 'snapshot-backup' AND status IN ('pending', 'running')
		AND json_extract(params, '$.targetDeviceSerial') = CAST($1 AS TEXT)`, "abc")
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var plan strings.Builder
	for rows.Next() {
		var line string
		if err := rows.Scan(&line); err != nil {
			t.Fatal(err)
		}
		plan.WriteString(line + "\n")
	}
	if !strings.Contains(plan.String(), "idx_jobs_backup_target") {
		t.Errorf("GetActiveBackupJob's predicate does not use idx_jobs_backup_target:\n%s", plan.String())
	}
}

// names lists the names of the jobs returned, sorted.
func names(jobs []db.Job) []string {
	out := []string{}
	for _, job := range jobs {
		out = append(out, job.Name)
	}
	sort.Strings(out)
	return out
}

// exerciseQuerier drives one engine's queries through db.Querier: each shape
// the generated code takes, and each query that was reworked to be shared or
// is written once per engine.
func exerciseQuerier(t *testing.T, conn *sql.DB) {
	t.Helper()
	ctx := context.Background()
	q := db.NewQueries(conn)
	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}

	// :one with a params struct, returning a model with defaults filled in.
	user, err := q.CreateUser(ctx, db.CreateUserParams{Username: "Ada", PasswordHash: "p", RecoveryPhraseHash: "r"})
	must(err)
	if user.ID == 0 || user.Status != "active" || user.IsAdmin != 0 || time.Since(user.CreatedAt).Abs() > time.Minute {
		t.Fatalf("CreateUser: %+v", user)
	}
	if _, err := q.CreateUser(ctx, db.CreateUserParams{Username: "Ada", PasswordHash: "p", RecoveryPhraseHash: "r"}); err == nil {
		t.Fatal("a second user named Ada was accepted")
	}
	// sql.ErrNoRows comes through untouched.
	if _, err := q.GetUserByUsername(ctx, "nobody"); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("GetUserByUsername(nobody) = %v, want sql.ErrNoRows", err)
	}
	other, err := q.CreateUser(ctx, db.CreateUserParams{Username: "Bob", PasswordHash: "p", RecoveryPhraseHash: "r"})
	must(err)

	// :many returning a row struct; :execrows; :exec; a 0/1 flag that stays a number.
	users, err := q.ListUsers(ctx)
	must(err)
	if len(users) != 2 || users[0].Username != "Ada" {
		t.Fatalf("ListUsers: %+v", users)
	}
	must(q.SetUserAdmin(ctx, db.SetUserAdminParams{IsAdmin: 1, Username: "Ada"}))
	if count, err := q.CountOtherActiveAdmins(ctx, other.ID); err != nil || count != 1 {
		t.Fatalf("CountOtherActiveAdmins = %d, %v", count, err)
	}

	// A time.Time in, compared with CURRENT_TIMESTAMP in the database.
	for token, expires := range map[string]time.Duration{"live": time.Hour, "expired": -time.Hour} {
		_, err := q.CreateSession(ctx, db.CreateSessionParams{Token: token, UserID: user.ID, ExpiresAt: time.Now().Add(expires), LastUsedAt: time.Now()})
		must(err)
	}
	sessions, err := q.ListActiveSessionsForUser(ctx, user.ID)
	must(err)
	if len(sessions) != 1 || sessions[0].Token != "live" {
		t.Fatalf("ListActiveSessionsForUser: %+v", sessions)
	}

	// A row that embeds a model (sqlc.embed), and a nullable column.
	calendar, err := q.GetDefaultCalendar(ctx)
	must(err)
	event, err := q.CreateCalendarEvent(ctx, db.CreateCalendarEventParams{
		CalendarID: calendar.ID, Title: "t", StartsAt: "2026-01-01T00:00:00Z", EndsAt: "2026-01-01T01:00:00Z",
		Repeat: "none", CreatedBy: sql.NullInt64{Int64: user.ID, Valid: true},
	})
	must(err)
	got, err := q.GetCalendarEvent(ctx, event.ID)
	must(err)
	if got.CalendarEvent.Title != "t" || got.OwnerName != "Ada" || got.CalendarEvent.ReminderMinutes.Valid {
		t.Fatalf("GetCalendarEvent: %+v", got)
	}

	// ListJobs and ListUserJobs, the two per-engine queries: sqlc.slice on
	// SQLite, an array on PostgreSQL. "scan" is a prefix of "scan.deep".
	owners := map[string]sql.NullInt64{"ada": {Int64: user.ID, Valid: true}, "bob": {Int64: other.ID, Valid: true}}
	for owner, id := range owners {
		for _, kind := range []string{"scan", "scan.deep", "convert"} {
			_, err := q.CreateJob(ctx, db.CreateJobParams{Kind: kind, Name: owner + ":" + kind, Params: "{}", UserID: id})
			must(err)
		}
	}
	for _, tc := range []struct {
		kinds []string
		want  []string
	}{
		{[]string{"scan", "convert"}, []string{"ada:convert", "ada:scan"}},
		{[]string{"scan"}, []string{"ada:scan"}},
		{[]string{"scan.deep", "nope"}, []string{"ada:scan.deep"}},
		{[]string{"sca"}, []string{}},
		{[]string{}, []string{}},
		{nil, []string{}},
	} {
		jobs, err := q.ListUserJobs(ctx, db.ListUserJobsParams{UserID: owners["ada"], Kinds: tc.kinds})
		must(err)
		if got := names(jobs); !reflect.DeepEqual(got, tc.want) {
			t.Errorf("ListUserJobs(ada, %q) = %v, want %v", tc.kinds, got, tc.want)
		}
	}
	for _, tc := range []struct {
		kinds []string
		want  []string
	}{
		{[]string{"scan", "convert"}, []string{"ada:convert", "ada:scan", "bob:convert", "bob:scan"}},
		{[]string{}, []string{}},
	} {
		jobs, err := q.ListJobs(ctx, tc.kinds)
		must(err)
		if got := names(jobs); !reflect.DeepEqual(got, tc.want) {
			t.Errorf("ListJobs(%q) = %v, want %v", tc.kinds, got, tc.want)
		}
	}

	// The lease queries: the database's clock, through datetime('now', ...).
	job, err := q.CreateJob(ctx, db.CreateJobParams{Kind: "lease", Name: "leased", Params: "{}", Lane: "x"})
	must(err)
	claimed, err := q.ClaimJob(ctx, db.ClaimJobParams{Owner: "me", ID: job.ID, LaneLimit: 1})
	must(err)
	if claimed.Status != "running" || !claimed.HeartbeatAt.Valid {
		t.Fatalf("ClaimJob: %+v", claimed)
	}
	// lapse backdates the job's heartbeat past any lease, in SQL both engines read.
	lapse := func() {
		t.Helper()
		_, err := conn.Exec(fmt.Sprintf(`UPDATE jobs SET heartbeat_at = '2000-01-01 00:00:00' WHERE id = %d`, job.ID))
		must(err)
	}
	if stale, err := q.RequeueStaleJobs(ctx, 3600); err != nil || len(stale) != 0 {
		t.Fatalf("RequeueStaleJobs = %+v, %v, want a job that just beat left alone", stale, err)
	}
	lapse()
	if failed, err := q.FailExhaustedStaleJobs(ctx, db.FailExhaustedStaleJobsParams{Reason: "gone", MaxAttempts: 2, LeaseSeconds: 3600}); err != nil || len(failed) != 0 {
		t.Fatalf("FailExhaustedStaleJobs = %+v, %v, want a first attempt left alone", failed, err)
	}
	if stale, err := q.RequeueStaleJobs(ctx, 3600); err != nil || len(stale) != 1 || stale[0].Status != "pending" {
		t.Fatalf("RequeueStaleJobs = %+v, %v, want the lapsed job requeued", stale, err)
	}
	_, err = q.ClaimJob(ctx, db.ClaimJobParams{Owner: "me", ID: job.ID, LaneLimit: 1})
	must(err)
	lapse()
	if failed, err := q.FailExhaustedStaleJobs(ctx, db.FailExhaustedStaleJobsParams{Reason: "gone", MaxAttempts: 2, LeaseSeconds: 3600}); err != nil || len(failed) != 1 || failed[0].Error != "gone" {
		t.Fatalf("FailExhaustedStaleJobs = %+v, %v, want the second attempt failed", failed, err)
	}
	must(q.EnsureMaintenanceRun(ctx, "prune"))
	for turn, want := range []int64{1, 0} {
		claimed, err := q.ClaimMaintenanceRun(ctx, db.ClaimMaintenanceRunParams{Owner: "me", Name: "prune", IntervalSeconds: 60})
		if err != nil || claimed != want {
			t.Fatalf("ClaimMaintenanceRun, turn %d = %d, %v, want %d", turn, claimed, err, want)
		}
	}

	// GetActiveBackupJob, on JSON in a column, and the unique index behind it.
	_, err = q.CreateJob(ctx, db.CreateJobParams{Kind: "snapshot-backup", Name: "backup", Params: `{"targetDeviceSerial":"abc"}`})
	must(err)
	if backup, err := q.GetActiveBackupJob(ctx, "abc"); err != nil || backup.Name != "backup" {
		t.Fatalf("GetActiveBackupJob(abc) = %+v, %v", backup, err)
	}
	if _, err := q.GetActiveBackupJob(ctx, "other"); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("GetActiveBackupJob(other) = %v, want sql.ErrNoRows", err)
	}
	if _, err := q.CreateJob(ctx, db.CreateJobParams{Kind: "snapshot-backup", Name: "second", Params: `{"targetDeviceSerial":"abc"}`}); err == nil {
		t.Fatal("idx_jobs_backup_target let a second active backup for one target through")
	}

	// RotateInstallID takes the id from Go.
	id := db.NewInstallID()
	must(q.RotateInstallID(ctx, id))
	if stored, err := q.GetInstallID(ctx); err != nil || stored != id {
		t.Fatalf("GetInstallID = %q, %v, want %q", stored, err, id)
	}

	// An upsert whose SET names the target row.
	_, err = q.UpsertConnectedDevice(ctx, db.UpsertConnectedDeviceParams{IpAddress: "1.2.3.4", UserAgent: "ua"})
	must(err)
	device, err := q.UpsertConnectedDevice(ctx, db.UpsertConnectedDeviceParams{IpAddress: "1.2.3.4", UserAgent: "ua"})
	must(err)
	if device.RequestCount != 2 {
		t.Fatalf("UpsertConnectedDevice count = %d, want 2", device.RequestCount)
	}

	// Case-insensitive uniqueness, and MoveAlbumItems and MoveFavorites, which
	// skip a row whose destination is taken where they once said OR IGNORE.
	album, err := q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "Trip", UserID: user.ID})
	must(err)
	if _, err := q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "TRIP", UserID: user.ID}); err == nil {
		t.Fatal("a sibling album whose name differs only in case was accepted")
	}
	for _, rel := range []string{"a/1.jpg", "a/sub/2.jpg", "b/sub/2.jpg", "ab/3.jpg"} {
		_, err := q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: album.ID, RelPath: rel})
		must(err)
		must(q.AddFavorite(ctx, db.AddFavoriteParams{UserID: user.ID, RelPath: rel}))
	}
	if _, err := q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: album.ID, RelPath: "a/1.jpg"}); err != nil {
		t.Fatalf("AddPhotoToAlbum twice: %v", err)
	}
	must(q.MoveAlbumItems(ctx, db.MoveAlbumItemsParams{NewRelPath: "b", OldRelPath: "a"}))
	must(q.MoveFavorites(ctx, db.MoveFavoritesParams{NewRelPath: "b", OldRelPath: "a"}))
	// a/sub/2.jpg collides with b/sub/2.jpg and is left behind; ab/ only shares a prefix.
	wantPaths := []string{"a/sub/2.jpg", "ab/3.jpg", "b/1.jpg", "b/sub/2.jpg"}
	items, err := q.ListAlbumItems(ctx, album.ID)
	must(err)
	favorites, err := q.ListFavorites(ctx, user.ID)
	must(err)
	itemPaths, favoritePaths := []string{}, []string{}
	for _, item := range items {
		itemPaths = append(itemPaths, item.RelPath)
	}
	for _, favorite := range favorites {
		favoritePaths = append(favoritePaths, favorite.RelPath)
	}
	sort.Strings(itemPaths)
	sort.Strings(favoritePaths)
	if !reflect.DeepEqual(itemPaths, wantPaths) || !reflect.DeepEqual(favoritePaths, wantPaths) {
		t.Fatalf("after the move: album items %v, favorites %v, want both %v", itemPaths, favoritePaths, wantPaths)
	}

	// BOOLEAN columns, a boolean result, and NULLS FIRST ordering.
	must(q.UpsertPhotoHash(ctx, db.UpsertPhotoHashParams{RelPath: "b/1.jpg"}))
	must(q.SetPhotoTakenAt(ctx, db.SetPhotoTakenAtParams{TakenAt: sql.NullTime{Time: time.Now(), Valid: true}, RelPath: "b/1.jpg"}))
	states, err := q.ListPhotoHashStates(ctx)
	must(err)
	if len(states) != 1 || !states[0].TakenChecked || states[0].HasContentHash {
		t.Fatalf("ListPhotoHashStates: %+v", states)
	}
	_, err = q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "Day one", UserID: user.ID, ParentID: sql.NullInt64{Int64: album.ID, Valid: true}})
	must(err)
	albums, err := q.ListAlbums(ctx, user.ID)
	must(err)
	if len(albums) != 2 || albums[0].ParentID.Valid || !albums[1].ParentID.Valid {
		t.Fatalf("ListAlbums did not put the root album first: %+v", albums)
	}
	if rows, err := q.UpsertDBVFSFile(ctx, db.UpsertDBVFSFileParams{Namespace: "ns", Path: "/f", Size: 1, Content: []byte("x")}); err != nil || rows != 1 {
		t.Fatalf("UpsertDBVFSFile = %d, %v", rows, err)
	}
	for range 2 {
		must(q.InsertDBVFSDirIfAbsent(ctx, db.InsertDBVFSDirIfAbsentParams{Namespace: "ns", Path: "/d"}))
	}
	if rows, err := q.UpsertDBVFSFile(ctx, db.UpsertDBVFSFileParams{Namespace: "ns", Path: "/d", Size: 1}); err != nil || rows != 0 {
		t.Fatalf("UpsertDBVFSFile over a directory = %d, %v, want 0 rows", rows, err)
	}

	// Two owners of one folder come back in the order they were granted, on
	// both engines: accessutil names the first as the folder's owner. Bob is
	// granted first and sorts after Ada by name and by id, so neither order
	// stands in for the one asked for.
	for _, grant := range []struct {
		path string
		id   int64
	}{{"shared/docs", other.ID}, {"shared/docs", user.ID}, {"shared", user.ID}} {
		must(q.SetUserPathAccess(ctx, db.SetUserPathAccessParams{
			RelPath: grant.path, UserID: sql.NullInt64{Int64: grant.id, Valid: true}, Level: "owner",
		}))
	}
	onAncestors, err := q.ListPathAccessOnAncestors(ctx, db.ListPathAccessOnAncestorsParams{RelPath: "shared/docs"})
	must(err)
	granted := []string{}
	for _, row := range onAncestors {
		granted = append(granted, row.RelPath+":"+row.Name)
	}
	if got := strings.Join(granted, " "); got != "shared:Ada shared/docs:Bob shared/docs:Ada" {
		t.Fatalf("ListPathAccessOnAncestors = %q, want shared:Ada shared/docs:Bob shared/docs:Ada", got)
	}

	// A transaction gets the same engine's queries as the pool, and an error
	// from the callback rolls it back.
	rolledBack := errors.New("roll this back")
	if err := db.InTx(ctx, conn, func(tx db.Querier) error {
		must(tx.DeleteUser(ctx, user.ID))
		return rolledBack
	}); !errors.Is(err, rolledBack) {
		t.Fatalf("InTx = %v, want the callback's error", err)
	}
	if _, err := q.GetUserByID(ctx, user.ID); err != nil {
		t.Fatalf("a rolled-back delete still removed the user: %v", err)
	}

	// Cascades are part of the schema on both engines.
	must(q.DeleteUser(ctx, user.ID))
	if left, err := q.ListAlbumItems(ctx, album.ID); err != nil || len(left) != 0 {
		t.Fatalf("deleting the user left album items: %v, %v", left, err)
	}

	// Music-library queries have no service caller yet; the next ticket adds
	// one. Run them here so both engines stay in step until then.
	exerciseMusic(ctx, t, q)
}

// exerciseMusic checks the music cache: upsert, the path prefix, a move, a
// device drop, the browse aggregates and the unchanged-file check.
func exerciseMusic(ctx context.Context, t *testing.T, q db.Querier) {
	t.Helper()
	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}
	track := func(serial, rel, artist, album, key, genre, cover string, year, duration, size int64) db.UpsertMusicTrackParams {
		p := db.UpsertMusicTrackParams{
			Serial: serial, RelPath: rel, Size: size, Mtime: 100, ScannerVersion: 1,
			Title: rel, Artist: artist, AlbumArtist: artist, Album: album, AlbumKey: key,
			Genre: genre, DurationExact: 1, CoverSource: cover, CoverKey: cover,
		}
		if year > 0 {
			p.Year = sql.NullInt64{Int64: year, Valid: true}
		}
		if duration > 0 {
			p.DurationMs = sql.NullInt64{Int64: duration, Valid: true}
		}
		return p
	}
	put := func(p db.UpsertMusicTrackParams) db.MusicTrack {
		t.Helper()
		row, err := q.UpsertMusicTrack(ctx, p)
		must(err)
		return row
	}
	scanPaths := func(serial string) []string {
		t.Helper()
		rows, err := q.ListMusicTrackScanStates(ctx, serial)
		must(err)
		out := make([]string, len(rows))
		for i, row := range rows {
			out[i] = fmt.Sprintf("%s:%d", row.RelPath, row.Size)
		}
		return out
	}
	albums := func(filter int64, artist string) []string {
		t.Helper()
		rows, err := q.ListMusicAlbums(ctx, db.ListMusicAlbumsParams{FilterArtist: filter, Artist: artist})
		must(err)
		out := make([]string, len(rows))
		for i, row := range rows {
			year := "null"
			if row.Year.Valid {
				year = fmt.Sprintf("%d", row.Year.Int64)
			}
			out[i] = fmt.Sprintf("%s|%s|%s|%s|%d|%d|%s|%s", row.AlbumKey, row.AlbumArtist, row.Title, year, row.TrackCount, row.DurationMs, row.CoverSerial, row.CoverPath)
		}
		return out
	}
	if got := albums(0, ""); len(got) != 0 {
		t.Fatalf("albums before any track: %v", got)
	}

	first := put(track("", "music/a/1.flac", "Nina", "Blue", "key-blue", "Rock", "", 2001, 100, 10))
	if again := put(track("", "music/a/1.flac", "Nina", "Blue", "key-blue", "Rock", "", 2001, 100, 10)); again.ID != first.ID || again.TrackNo.Valid {
		t.Fatalf("second upsert = %+v, want id %d and a null track number", again, first.ID)
	}
	replaced := track("", "music/a/1.flac", "Nina", "Blue", "key-blue", "Rock", "", 2001, 100, 10)
	replaced.Title = "One"
	if got := put(replaced); got.ID != first.ID || got.Title != "One" || got.Size != 10 {
		t.Fatalf("replacement upsert = %+v", got)
	}
	put(track("", "music/a/2.flac", "Nina", "Blue", "key-blue", "rock", "embedded", 0, 50, 20))
	put(track("", "music/ab/3.flac", "Nina", "Red", "key-red", "Jazz", "", 1999, 80, 30))
	gold := track("", "music/c/4.flac", "Sam", "Gold", "key-gold", "", "folder:cover.jpg", 1980, 0, 40)
	gold.DurationExact = 0
	if got := put(gold); got.DurationExact != 0 || got.DurationMs.Valid || !got.Year.Valid || got.Year.Int64 != 1980 {
		t.Fatalf("gold track = %+v", got)
	}
	put(track("", "loose/6.flac", "", "", "key-loose", "Pop", "", 0, 0, 1))
	put(track("usb", "x/5.flac", "nina", "Blue", "key-blue-usb", "ROCK", "", 2001, 10, 5))

	state, err := q.GetMusicTrackScanState(ctx, db.GetMusicTrackScanStateParams{RelPath: "music/a/1.flac"})
	must(err)
	if state.Size != 10 || state.Mtime != 100 || state.ScannerVersion != 1 {
		t.Fatalf("scan state = %+v", state)
	}
	if _, err := q.GetMusicTrackScanState(ctx, db.GetMusicTrackScanStateParams{RelPath: "missing.flac"}); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("missing scan state = %v, want sql.ErrNoRows", err)
	}
	if got, want := scanPaths(""), []string{
		"loose/6.flac:1", "music/a/1.flac:10", "music/a/2.flac:20", "music/ab/3.flac:30", "music/c/4.flac:40",
	}; !reflect.DeepEqual(got, want) {
		t.Fatalf("internal scan states = %v, want %v", got, want)
	}
	if got, want := scanPaths("usb"), []string{"x/5.flac:5"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("usb scan states = %v, want %v", got, want)
	}

	wantAlbums := []string{
		"key-loose|||null|1|0||loose/6.flac",
		"key-blue|Nina|Blue|2001|2|150||music/a/2.flac",
		"key-blue-usb|nina|Blue|2001|1|10|usb|x/5.flac",
		"key-red|Nina|Red|1999|1|80||music/ab/3.flac",
		"key-gold|Sam|Gold|1980|1|0||music/c/4.flac",
	}
	if got := albums(0, "ignored"); !reflect.DeepEqual(got, wantAlbums) {
		t.Fatalf("albums = %v, want %v", got, wantAlbums)
	}
	if got, want := albums(1, "NINA"), []string{
		"key-blue|Nina|Blue|2001|2|150||music/a/2.flac",
		"key-blue-usb|nina|Blue|2001|1|10|usb|x/5.flac",
		"key-red|Nina|Red|1999|1|80||music/ab/3.flac",
	}; !reflect.DeepEqual(got, want) {
		t.Fatalf("Nina's albums = %v, want %v", got, want)
	}
	if got, want := albums(1, ""), []string{"key-loose|||null|1|0||loose/6.flac"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("untagged albums = %v, want %v", got, want)
	}

	artists, err := q.ListMusicArtists(ctx)
	must(err)
	gotArtists := make([]string, len(artists))
	for i, row := range artists {
		gotArtists[i] = fmt.Sprintf("%s|%d|%d|%s|%s", strings.ToLower(row.Name), row.AlbumCount, row.TrackCount, row.CoverSerial, row.CoverPath)
	}
	wantArtists := []string{"|1|1||loose/6.flac", "nina|3|4||music/a/2.flac", "sam|1|1||music/c/4.flac"}
	if !reflect.DeepEqual(gotArtists, wantArtists) {
		t.Fatalf("artists = %v, want %v", gotArtists, wantArtists)
	}

	genres, err := q.ListMusicGenres(ctx)
	must(err)
	gotGenres := make([]string, len(genres))
	for i, row := range genres {
		gotGenres[i] = fmt.Sprintf("%s|%d", strings.ToLower(row.Name), row.TrackCount)
	}
	wantGenres := []string{"|1", "jazz|1", "pop|1", "rock|3"}
	if !reflect.DeepEqual(gotGenres, wantGenres) {
		t.Fatalf("genres = %v, want %v", gotGenres, wantGenres)
	}

	// A '%' or '_' in a name is not a wildcard, and a prefix matches characters,
	// so "caf" does not eat "aé".
	put(track("", "100%_done/t.flac", "Ada", "Pct", "key-pct", "Pop", "", 2002, 1, 2))
	put(track("", "100/nope.flac", "Ada", "Other", "key-other", "Pop", "", 2002, 1, 3))
	put(track("", "aé/b.flac", "Ada", "Accent", "key-accent", "Pop", "", 2003, 1, 4))
	must(q.DeleteMusicTracksUnder(ctx, db.DeleteMusicTracksUnderParams{RelPath: "100"}))
	if _, err := q.GetMusicTrackScanState(ctx, db.GetMusicTrackScanStateParams{RelPath: "100/nope.flac"}); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("100/nope.flac survived a delete of 100: %v", err)
	}
	if _, err := q.GetMusicTrackScanState(ctx, db.GetMusicTrackScanStateParams{RelPath: "100%_done/t.flac"}); err != nil {
		t.Fatalf("100%%_done was treated as a wildcard: %v", err)
	}
	must(q.DeleteMusicTracksUnder(ctx, db.DeleteMusicTracksUnderParams{RelPath: "100%_done"}))
	if _, err := q.GetMusicTrackScanState(ctx, db.GetMusicTrackScanStateParams{RelPath: "100%_done/t.flac"}); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("100%%_done/t.flac survived its own prefix: %v", err)
	}
	must(q.DeleteMusicTracksUnder(ctx, db.DeleteMusicTracksUnderParams{RelPath: "caf"}))
	if _, err := q.GetMusicTrackScanState(ctx, db.GetMusicTrackScanStateParams{RelPath: "aé/b.flac"}); err != nil {
		t.Fatalf("aé/b.flac was deleted by the prefix caf: %v", err)
	}
	must(q.DeleteMusicTracksUnder(ctx, db.DeleteMusicTracksUnderParams{RelPath: "aé"}))
	if _, err := q.GetMusicTrackScanState(ctx, db.GetMusicTrackScanStateParams{RelPath: "aé/b.flac"}); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("aé/b.flac survived its prefix: %v", err)
	}

	must(q.MoveMusicTracks(ctx, db.MoveMusicTracksParams{OldRelPath: "music/a", NewRelPath: "moved/a"}))
	if got, want := scanPaths(""), []string{
		"loose/6.flac:1", "moved/a/1.flac:10", "moved/a/2.flac:20", "music/ab/3.flac:30", "music/c/4.flac:40",
	}; !reflect.DeepEqual(got, want) {
		t.Fatalf("after the move, scan states = %v, want %v", got, want)
	}
	if got := albums(1, "Nina"); len(got) != 3 || !strings.Contains(got[0], "key-blue|Nina|Blue|2001|2|150||moved/a/2.flac") {
		t.Fatalf("moved album = %v, want key-blue still grouped with the new cover path", got)
	}
	moved, err := q.GetMusicTrackScanState(ctx, db.GetMusicTrackScanStateParams{RelPath: "moved/a/1.flac"})
	must(err)
	if moved.Size != 10 || moved.ScannerVersion != 1 {
		t.Fatalf("moved scan state = %+v", moved)
	}
	if _, err := q.GetMusicTrackScanState(ctx, db.GetMusicTrackScanStateParams{RelPath: "music/a/1.flac"}); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("old path still indexed: %v", err)
	}

	// The destination is already a track, so the statement fails and neither row moves.
	if err := q.MoveMusicTracks(ctx, db.MoveMusicTracksParams{OldRelPath: "music/ab/3.flac", NewRelPath: "music/c/4.flac"}); err == nil {
		t.Fatal("a move onto an indexed path was accepted")
	}
	if _, err := q.GetMusicTrackScanState(ctx, db.GetMusicTrackScanStateParams{RelPath: "music/ab/3.flac"}); err != nil {
		t.Fatalf("source of the refused move is gone: %v", err)
	}
	if _, err := q.GetMusicTrackScanState(ctx, db.GetMusicTrackScanStateParams{RelPath: "music/c/4.flac"}); err != nil {
		t.Fatalf("destination of the refused move is gone: %v", err)
	}

	must(q.DeleteMusicTracksUnder(ctx, db.DeleteMusicTracksUnderParams{RelPath: "moved/a"}))
	// An exact file, not a folder: the rewritten path has no suffix left over.
	must(q.MoveMusicTracks(ctx, db.MoveMusicTracksParams{OldRelPath: "loose/6.flac", NewRelPath: "loose/moved.flac"}))
	if _, err := q.GetMusicTrackScanState(ctx, db.GetMusicTrackScanStateParams{RelPath: "loose/moved.flac"}); err != nil {
		t.Fatalf("exact file move: %v", err)
	}
	must(q.DeleteMusicTracksUnder(ctx, db.DeleteMusicTracksUnderParams{RelPath: "loose/moved.flac"}))
	must(q.DeleteMusicTracksBySerial(ctx, "usb"))
	if got, want := scanPaths("usb"), []string{}; !reflect.DeepEqual(got, want) {
		t.Fatalf("usb after drop = %v", got)
	}
	if got, want := scanPaths(""), []string{"music/ab/3.flac:30", "music/c/4.flac:40"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("internal after the deletes = %v, want %v", got, want)
	}
	must(q.DeleteMusicTracksBySerial(ctx, ""))
	if got := albums(0, ""); len(got) != 0 {
		t.Fatalf("albums after dropping the internal drive: %v", got)
	}
}
