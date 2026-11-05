package v0_files_test

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/gin-gonic/gin"
)

type listedSession struct {
	SessionID string `json:"sessionId"`
	FileName  string `json:"fileName"`
	TotalSize int64  `json:"totalSize"`
	Offset    int64  `json:"offset"`
	State     string `json:"state"`
}

type listedSessions struct {
	Active   []listedSession `json:"active"`
	Finished []listedSession `json:"finished"`
}

func listSessions(t *testing.T, engine *gin.Engine) listedSessions {
	t.Helper()
	w := doRequest(engine, http.MethodGet, "/api/v0/files/upload-sessions", nil, "")
	if w.Code != http.StatusOK {
		t.Fatalf("list returned %d: %s", w.Code, w.Body.String())
	}
	var decoded listedSessions
	if err := json.Unmarshal(w.Body.Bytes(), &decoded); err != nil {
		t.Fatalf("decode list: %v\nbody: %s", err, w.Body.String())
	}
	return decoded
}

// GET /files/upload-sessions is what the Jobs page shows for uploads (#3971):
// a session in flight with what it has committed, and then how it ended.
func TestListUploadSessionsFollowsAnUpload(t *testing.T) {
	deps, _ := newStorageVFSDeps(t)
	engine := newEngineForDeps(deps)
	events, unsubscribe := deps.EventBus().Subscribe("test")
	t.Cleanup(unsubscribe)

	if got := listSessions(t, engine); got.Active == nil || got.Finished == nil || len(got.Active)+len(got.Finished) != 0 {
		t.Fatalf("an empty store listed %+v, want two empty arrays", got)
	}

	content := randomContent(t, 3*uploadChunkSize)
	id := openSessionOK(t, engine, "", "big.bin", len(content))
	if w := putSlice(t, engine, id, content, 0, uploadChunkSize); w.Code != http.StatusOK {
		t.Fatalf("first chunk returned %d: %s", w.Code, w.Body.String())
	}

	got := listSessions(t, engine)
	if len(got.Active) != 1 {
		t.Fatalf("active is %+v, want the one session", got.Active)
	}
	if s := got.Active[0]; s.SessionID != id || s.FileName != "big.bin" || s.TotalSize != int64(len(content)) ||
		s.Offset != uploadChunkSize || s.State != "uploading" {
		t.Errorf("in-flight session listed as %+v", s)
	}

	for start := uploadChunkSize; start < len(content); start += uploadChunkSize {
		if w := putSlice(t, engine, id, content, start, start+uploadChunkSize); w.Code != http.StatusOK {
			t.Fatalf("chunk at %d returned %d: %s", start, w.Code, w.Body.String())
		}
	}

	got = listSessions(t, engine)
	if len(got.Active) != 0 || len(got.Finished) != 1 || got.Finished[0].SessionID != id || got.Finished[0].State != "completed" {
		t.Errorf("after the commit the list is %+v", got)
	}

	// Opening and finishing are news; the middle chunk, well inside
	// ProgressInterval, is not.
	var hints int
	for done := false; !done; {
		select {
		case evt := <-events:
			if evt.Kind != eventbus.EventUploadSessionChanged {
				continue
			}
			changed, ok := evt.Data.(eventbus.UploadSessionChanged)
			if !ok || changed.SessionID != id {
				t.Errorf("event data is %#v", evt.Data)
			}
			hints++
		default:
			done = true
		}
	}
	if hints != 2 {
		t.Errorf("published %d upload_session_changed events, want 2 (opened, completed)", hints)
	}
}

func TestDeletingAnUploadSessionListsItAsCanceled(t *testing.T) {
	engine, _, _ := newUploadSessionEngine(t)
	id := openSessionOK(t, engine, "", "gone.bin", 1024)
	if w := doRequest(engine, http.MethodDelete, "/api/v0/files/upload-session/"+id, nil, ""); w.Code != http.StatusOK {
		t.Fatalf("delete returned %d: %s", w.Code, w.Body.String())
	}
	got := listSessions(t, engine)
	if len(got.Active) != 0 || len(got.Finished) != 1 || got.Finished[0].State != "canceled" {
		t.Errorf("after a delete the list is %+v", got)
	}
}
