package db_test

import (
	"context"
	"database/sql"
	"errors"
	"reflect"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
)

// The music cache's defaults, indexes and FTS5 triggers. MATCH is not a sqlc
// query: FTS5 is SQLite only, and the search statement lands with the library
// service behind db.RequireSQLite.
func TestMusicLibrarySchema(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	conn := database.Db

	var triggers []string
	rows, err := conn.Query(`SELECT name FROM sqlite_master WHERE type = 'trigger' AND tbl_name = 'music_tracks' ORDER BY name`)
	if err != nil {
		t.Fatal(err)
	}
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			t.Fatal(err)
		}
		triggers = append(triggers, name)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	wantTriggers := []string{"music_tracks_ad", "music_tracks_ai", "music_tracks_au"}
	if !reflect.DeepEqual(triggers, wantTriggers) {
		t.Fatalf("triggers = %v, want %v", triggers, wantTriggers)
	}
	for _, index := range []string{"idx_music_tracks_album", "idx_music_tracks_artist", "idx_music_tracks_genre"} {
		var n int
		if err := conn.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = ?`, index).Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n != 1 {
			t.Errorf("index %s missing", index)
		}
	}

	if _, err := conn.ExecContext(ctx, `INSERT INTO music_tracks (serial, rel_path, size, mtime, scanner_version) VALUES ('', 'bare.mp3', 1, 2, 3)`); err != nil {
		t.Fatal(err)
	}
	var title, cover string
	var exact int64
	var trackNo sql.NullInt64
	if err := conn.QueryRowContext(ctx, `SELECT title, duration_exact, track_no, cover_source FROM music_tracks WHERE rel_path = 'bare.mp3'`).Scan(&title, &exact, &trackNo, &cover); err != nil {
		t.Fatal(err)
	}
	if title != "" || cover != "" || exact != 1 || trackNo.Valid {
		t.Fatalf("defaults: title %q cover %q exact %d track %v", title, cover, exact, trackNo)
	}
	var indexed int
	if err := conn.QueryRowContext(ctx, `SELECT COUNT(*) FROM music_tracks_fts WHERE rowid = (SELECT id FROM music_tracks WHERE rel_path = 'bare.mp3')`).Scan(&indexed); err != nil {
		t.Fatal(err)
	}
	if indexed != 1 {
		t.Fatalf("insert trigger indexed %d rows, want 1", indexed)
	}
	if _, err := conn.ExecContext(ctx, `INSERT INTO music_tracks (serial, rel_path, size, mtime, scanner_version) VALUES ('', 'bare.mp3', 1, 2, 3)`); err == nil {
		t.Fatal("a second row for the same file was accepted")
	}
}

func TestMusicTrackFTSFollowsWrites(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	q := database.Queries

	put := func(rel, title, artist string) {
		t.Helper()
		_, err := q.UpsertMusicTrack(ctx, db.UpsertMusicTrackParams{
			Serial: "", RelPath: rel, Size: 1, Mtime: 1, ScannerVersion: 1,
			Title: title, Artist: artist, AlbumArtist: artist, Album: "Blue", AlbumKey: "key",
			DurationExact: 1,
		})
		if err != nil {
			t.Fatal(err)
		}
	}
	match := func(query string) []string {
		t.Helper()
		// FTS5 MATCH is SQLite only and not in the sqlc set.
		rows, err := database.Db.QueryContext(ctx, `
			SELECT music_tracks.rel_path
			FROM music_tracks_fts
			JOIN music_tracks ON music_tracks.id = music_tracks_fts.rowid
			WHERE music_tracks_fts MATCH ?
			ORDER BY music_tracks.rel_path`, query)
		if err != nil {
			t.Fatal(err)
		}
		defer rows.Close()
		var got []string
		for rows.Next() {
			var path string
			if err := rows.Scan(&path); err != nil {
				t.Fatal(err)
			}
			got = append(got, path)
		}
		if err := rows.Err(); err != nil {
			t.Fatal(err)
		}
		if got == nil {
			got = []string{}
		}
		return got
	}

	put("music/a.flac", "Café", "Nina")
	if got, want := match("cafe"), []string{"music/a.flac"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("MATCH cafe = %v, want %v", got, want)
	}
	if got, want := match("artist : nina"), []string{"music/a.flac"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("MATCH artist = %v, want %v", got, want)
	}
	if got := match("artist : sam"); len(got) != 0 {
		t.Fatalf("MATCH sam = %v, want none", got)
	}

	put("music/a.flac", "Café", "Sam")
	if got := match("nina"); len(got) != 0 {
		t.Fatalf("after the artist change MATCH nina = %v", got)
	}
	if got, want := match("sam"), []string{"music/a.flac"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("after the artist change MATCH sam = %v, want %v", got, want)
	}

	if err := q.MoveMusicTracks(ctx, db.MoveMusicTracksParams{OldRelPath: "music/a.flac", NewRelPath: "moved/a.flac"}); err != nil {
		t.Fatal(err)
	}
	if got, want := match("cafe"), []string{"moved/a.flac"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("after the move MATCH cafe = %v, want %v", got, want)
	}

	if err := q.DeleteMusicTracksUnder(ctx, db.DeleteMusicTracksUnderParams{RelPath: "moved/a.flac"}); err != nil {
		t.Fatal(err)
	}
	if got := match("cafe"); len(got) != 0 {
		t.Fatalf("after the delete MATCH cafe = %v", got)
	}
	if _, err := q.GetMusicTrackScanState(ctx, db.GetMusicTrackScanStateParams{RelPath: "moved/a.flac"}); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("deleted track still has a scan state: %v", err)
	}
}
