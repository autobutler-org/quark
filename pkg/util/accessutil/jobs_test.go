package accessutil_test

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
)

func job(userID int64, params string) jobutil.Job {
	return jobutil.Job{ID: 7, UserID: userID, Params: json.RawMessage(params), Error: "ffmpeg: /srv/quark/files/a.mkv: boom"}
}

func TestCanSeeJob(t *testing.T) {
	f := newFixture(t)
	carol := createUser(t, f.database, "carol")
	f.grant(t, f.userID, "", "shared", accessutil.Read)
	bob := f.load(t, accessutil.Principal{UserID: f.userID})
	admin := f.load(t, accessutil.System)

	for _, tc := range []struct {
		name   string
		access accessutil.Access
		job    jobutil.Job
		want   bool
	}{
		{"admin sees a job with no creator", admin, job(0, `{"relPath":"private/a.mkv"}`), true},
		{"admin sees another account's job", admin, job(carol, `{"relPath":"private/a.mkv"}`), true},
		{"own job on a readable file", bob, job(f.userID, `{"relPath":"shared/a.mkv"}`), true},
		{"own job on no file", bob, job(f.userID, `{}`), true},
		{"own job on a file no longer readable", bob, job(f.userID, `{"relPath":"private/a.mkv"}`), false},
		{"own job on a device not attached", bob, job(f.userID, `{"serial":"USB-9","relPath":"shared/a.mkv"}`), false},
		{"another account's job on a shared file", bob, job(carol, `{"relPath":"shared/a.mkv"}`), false},
		{"a job with no creator", bob, job(0, `{}`), false},
		{"nobody", f.load(t, accessutil.Principal{}), job(0, `{}`), false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := tc.access.CanSeeJob(tc.job); got != tc.want {
				t.Errorf("CanSeeJob = %v, want %v", got, tc.want)
			}
		})
	}

	jobs := []jobutil.Job{job(carol, `{"relPath":"shared/a.mkv"}`), job(f.userID, `{"relPath":"shared/b.mkv"}`)}
	if got := accessutil.VisibleJobs(accessutil.VisibleJobsParams{Access: bob, Jobs: jobs}).Jobs; len(got) != 1 ||
		got[0].UserID != f.userID || got[0].Error != "" {
		t.Errorf("VisibleJobs for bob = %+v, want only his job with its error blank", got)
	}
	if got := accessutil.VisibleJobs(accessutil.VisibleJobsParams{Access: admin, Jobs: jobs}).Jobs; len(got) != 2 || got[0].Error == "" {
		t.Errorf("VisibleJobs for an admin = %+v, want both with their errors", got)
	}
	if got := accessutil.VisibleJobs(accessutil.VisibleJobsParams{Access: bob}).Jobs; got == nil {
		t.Error("VisibleJobs of nothing is nil, want an empty slice")
	}
}

func TestLoadCreator(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	f.grant(t, f.userID, "", "shared", accessutil.Write)
	load := func(userID int64) (accessutil.Access, error) {
		result, err := accessutil.LoadCreator(accessutil.LoadCreatorParams{Ctx: ctx, Database: f.database, Storage: f.storage, UserID: userID})
		return result.Access, err
	}

	if access, err := load(0); err != nil || access.Principal() != accessutil.System {
		t.Errorf("LoadCreator with no creator = %+v, %v, want System", access.Principal(), err)
	}
	access, err := load(f.userID)
	if err != nil || access.Principal() != (accessutil.Principal{UserID: f.userID}) || !access.Check("", "shared", accessutil.Write).Allowed {
		t.Errorf("LoadCreator for bob = %+v, %v, want his rows loaded", access.Principal(), err)
	}

	root := createUser(t, f.database, "root")
	if err := f.database.Queries.SetUserAdmin(ctx, db.SetUserAdminParams{IsAdmin: 1, Username: "root"}); err != nil {
		t.Fatal(err)
	}
	if access, err := load(root); err != nil || access.Principal() != (accessutil.Principal{UserID: root, IsAdmin: true}) {
		t.Errorf("LoadCreator for an admin = %+v, %v, want an admin principal", access.Principal(), err)
	}

	dora := createUser(t, f.database, "dora")
	if _, err := f.database.Queries.SetUserStatus(ctx, db.SetUserStatusParams{
		ToStatus: authutil.StatusDisabled, Username: "dora", FromStatus: authutil.StatusActive,
	}); err != nil {
		t.Fatal(err)
	}
	for name, userID := range map[string]int64{"disabled": dora, "deleted": 9999} {
		if _, err := load(userID); !errors.Is(err, accessutil.ErrCreatorInactive) {
			t.Errorf("LoadCreator for a %s account = %v, want ErrCreatorInactive", name, err)
		}
	}
	if _, err := accessutil.LoadCreator(accessutil.LoadCreatorParams{Ctx: ctx, UserID: f.userID}); !errors.Is(err, accessutil.ErrNoDatabase) {
		t.Errorf("LoadCreator with no database = %v, want ErrNoDatabase", err)
	}
}

func TestFilterEventJobs(t *testing.T) {
	f := newFixture(t)
	carol := f.load(t, accessutil.Principal{UserID: createUser(t, f.database, "carol")})
	revoked := f.load(t, accessutil.Principal{UserID: f.userID})
	f.grant(t, f.userID, "", "shared", accessutil.Read)
	bob := f.load(t, accessutil.Principal{UserID: f.userID})
	admin := f.load(t, accessutil.System)
	own := job(f.userID, `{"relPath":"shared/a.mkv"}`)

	for _, kind := range []eventbus.EventKind{
		eventbus.EventJobQueued, eventbus.EventJobStarted, eventbus.EventJobProgress,
		eventbus.EventJobCompleted, eventbus.EventJobFailed, eventbus.EventJobCanceled,
	} {
		t.Run(string(kind), func(t *testing.T) {
			filter := func(access accessutil.Access, data any) accessutil.FilterEventResult {
				return accessutil.FilterEvent(accessutil.FilterEventParams{Access: access, Event: eventbus.Event{Kind: kind, Data: data}})
			}
			got := filter(bob, own)
			if delivered, ok := got.Event.Data.(jobutil.Job); !got.Deliver || !ok || delivered.ID != own.ID ||
				delivered.Error != "" || got.Event.Path != "" || got.Event.Kind != kind {
				t.Errorf("creator hears %+v (deliver %v), want the job with its error blank", got.Event, got.Deliver)
			}
			if got := filter(admin, own); !got.Deliver || got.Event.Data.(jobutil.Job).Error != own.Error {
				t.Errorf("admin hears %+v (deliver %v), want the job unchanged", got.Event, got.Deliver)
			}
			for name, tc := range map[string]struct {
				access accessutil.Access
				data   any
			}{
				"another account":          {carol, own},
				"creator who lost access":  {revoked, own},
				"a job with no creator":    {bob, job(0, `{}`)},
				"data that is not a job":   {bob, map[string]any{"id": 7}},
				"a job queued by somebody": {bob, job(9999, `{}`)},
			} {
				if got := filter(tc.access, tc.data); got.Deliver {
					t.Errorf("%s hears %+v, want it dropped", name, got.Event)
				}
			}
		})
	}
}
