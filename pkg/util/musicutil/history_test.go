package musicutil_test

import (
	"context"
	"encoding/json"
	"errors"
	"reflect"
	"strconv"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/musicutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// historyLibrary is the shared library and the metadata store plays go to.
func historyLibrary(t *testing.T) (*musicutil.ListHistoryParams, *db.DatabaseSqlc) {
	t.Helper()
	database := library(t)
	return &musicutil.ListHistoryParams{
		Ctx: context.Background(), DB: database.Db, Store: vfs.NewSQLiteMetadataStore(database.Db),
		Serials: []string{"", usbSerial},
	}, database
}

func play(t *testing.T, params *musicutil.ListHistoryParams, access accessutil.Access, relPath string) (musicutil.Plays, error) {
	t.Helper()
	result, err := musicutil.RecordPlay(musicutil.RecordPlayParams{
		Ctx: params.Ctx, DB: params.DB, Store: params.Store, Access: access, Serial: usbSerial, RelPath: relPath,
	})
	return result.Plays, err
}

func history(t *testing.T, params musicutil.ListHistoryParams, access accessutil.Access, sort musicutil.HistorySort) []musicutil.PlayedTrack {
	t.Helper()
	params.Access, params.Sort = access, sort
	result, err := musicutil.ListHistory(params)
	if err != nil {
		t.Fatal(err)
	}
	return result.Tracks
}

func playedTitles(tracks []musicutil.PlayedTrack) []string {
	out := []string{}
	for _, p := range tracks {
		out = append(out, p.Track.Title)
	}
	return out
}

func TestRecordPlay_CountsAndStamps(t *testing.T) {
	params, _ := historyLibrary(t)
	admin := adminAccess(t)
	before := time.Now().UTC().Add(-time.Second)
	for want := 1; want <= 3; want++ {
		plays, err := play(t, params, admin, "/shared/solo/1.flac")
		if err != nil {
			t.Fatal(err)
		}
		if plays.Count != want || plays.LastPlayedAt.Before(before) {
			t.Fatalf("play %d stored %+v", want, plays)
		}
	}
	got := history(t, *params, admin, musicutil.HistoryRecent)
	if len(got) != 1 || got[0].Track.Title != "Gamma" || got[0].PlayCount != 3 || got[0].Track.Serial != usbSerial {
		t.Errorf("history = %+v, want Gamma played 3 times", got)
	}
}

func TestRecordPlay_RefusesWhatIsNotAReadableTrack(t *testing.T) {
	params, database := historyLibrary(t)
	member := memberAccess(t, database, "shared")
	cases := []struct {
		name    string
		access  accessutil.Access
		relPath string
	}{
		{name: "not in the library", access: adminAccess(t), relPath: "shared/solo/missing.flac"},
		{name: "not readable", access: member, relPath: "private/secret/1.flac"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := play(t, params, tc.access, tc.relPath); !errors.Is(err, musicutil.ErrTrackNotFound) {
				t.Errorf("err = %v, want ErrTrackNotFound", err)
			}
		})
	}
}

func TestListHistory_Orders(t *testing.T) {
	params, _ := historyLibrary(t)
	admin := adminAccess(t)
	base := time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC)
	// Gamma played most but longest ago; Delta most recently.
	for _, p := range []struct {
		path  string
		count int
		at    time.Time
	}{
		{"shared/solo/1.flac", 5, base},
		{"shared/mixed/1.flac", 2, base.Add(time.Hour)},
		{"private/mixed/3.flac", 2, base.Add(2 * time.Hour)},
	} {
		raw, _ := json.Marshal(musicutil.Plays{Count: p.count, LastPlayedAt: p.at})
		key := "music.plays." + strconv.FormatInt(admin.Principal().UserID, 10)
		if err := params.Store.Set(params.Ctx, vfs.FilesNamespace(usbSerial), p.path, map[string]json.RawMessage{key: raw}); err != nil {
			t.Fatal(err)
		}
	}
	cases := []struct {
		sort musicutil.HistorySort
		want []string
	}{
		{sort: "", want: []string{"Delta", "Alpha", "Gamma"}},
		{sort: musicutil.HistoryRecent, want: []string{"Delta", "Alpha", "Gamma"}},
		// Alpha and Delta tie on count; the more recent play goes first.
		{sort: musicutil.HistoryMost, want: []string{"Gamma", "Delta", "Alpha"}},
	}
	for _, tc := range cases {
		if got := playedTitles(history(t, *params, admin, tc.sort)); !reflect.DeepEqual(got, tc.want) {
			t.Errorf("sort %q = %v, want %v", tc.sort, got, tc.want)
		}
	}
	limited := *params
	limited.Access, limited.Limit = admin, 2
	result, err := musicutil.ListHistory(limited)
	if err != nil || len(result.Tracks) != 2 {
		t.Errorf("limit 2 = %d tracks, %v", len(result.Tracks), err)
	}
	limited.Sort = "loudest"
	if _, err := musicutil.ListHistory(limited); !errors.Is(err, musicutil.ErrInvalidHistorySort) {
		t.Errorf("unknown sort err = %v, want ErrInvalidHistorySort", err)
	}
}

func TestListHistory_PerAccountAndOnlyLiveReadableTracks(t *testing.T) {
	params, database := historyLibrary(t)
	admin := adminAccess(t)
	for _, p := range []string{"shared/mixed/1.flac", "private/secret/1.flac", "shared/solo/1.flac"} {
		if _, err := play(t, params, admin, p); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := musicutil.DeletePath(musicutil.DeletePathParams{
		Ctx: params.Ctx, DB: params.DB, Serial: usbSerial, RelPath: "shared/solo",
	}); err != nil {
		t.Fatal(err)
	}
	if got := playedTitles(history(t, *params, admin, musicutil.HistoryMost)); !reflect.DeepEqual(got, []string{"Alpha", "Epsilon"}) {
		t.Errorf("admin history = %v, want the deleted track left out", got)
	}
	member := memberAccess(t, database, "shared")
	if got := history(t, *params, member, musicutil.HistoryRecent); len(got) != 0 {
		t.Errorf("member history = %v, want none of the admin's plays", playedTitles(got))
	}
}
