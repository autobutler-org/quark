package v0_ssh_test

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	v0_ssh "github.com/autobutler-org/quark/internal/server/api/v0/ssh"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/sshutil"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/ssh"
)

type sshHarness struct {
	engine *gin.Engine
	// calls records every command the handlers ran, stdin included.
	calls *[][]string
}

func newSSHHarness(t *testing.T, reason sshutil.Reason) sshHarness {
	t.Helper()
	calls := &[][]string{}
	system := sshutil.System{
		Unavailable: func() sshutil.Reason { return reason },
		Run: func(_ context.Context, stdin io.Reader, name string, args ...string) ([]byte, error) {
			in := ""
			if stdin != nil {
				b, err := io.ReadAll(stdin)
				if err != nil {
					t.Fatal(err)
				}
				in = string(b)
			}
			*calls = append(*calls, append(append([]string{name}, args...), "stdin="+in))
			return nil, nil
		},
		AuthorizedKeysPath: filepath.Join(t.TempDir(), ".ssh", "authorized_keys"),
	}
	deps := deputil.NewDependencies().WithSSHSystem(system)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_ssh.NewRouter())
	return sshHarness{engine: engine, calls: calls}
}

func (h sshHarness) do(method, path, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, req)
	return w
}

type statusBody struct {
	Available bool          `json:"available"`
	Reason    string        `json:"reason"`
	Enabled   bool          `json:"enabled"`
	Keys      []sshutil.Key `json:"keys"`
}

func (h sshHarness) status(t *testing.T) statusBody {
	t.Helper()
	w := h.do(http.MethodGet, "/api/v0/ssh/status", "")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", w.Code, w.Body.String())
	}
	var got statusBody
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	return got
}

func publicKeyLine(t *testing.T) (string, string) {
	t.Helper()
	pub, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	sshPub, err := ssh.NewPublicKey(pub)
	if err != nil {
		t.Fatal(err)
	}
	return strings.TrimSpace(string(ssh.MarshalAuthorizedKey(sshPub))) + " admin@laptop", ssh.FingerprintSHA256(sshPub)
}

func jsonBody(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// TestSSH_Endpoints drives every route against a host that can manage SSH:
// on and off run the helper through sudo, keys round-trip through the file,
// and the password reaches the helper on stdin only.
func TestSSH_Endpoints(t *testing.T) {
	h := newSSHHarness(t, sshutil.ReasonNone)

	if got := h.status(t); !got.Available || got.Keys == nil || len(got.Keys) != 0 {
		t.Errorf("fresh status = %+v, want available with an empty key list", got)
	}

	for body, action := range map[string]string{`{"enabled":true}`: "enable", `{"enabled":false}`: "disable"} {
		*h.calls = nil
		if w := h.do(http.MethodPut, "/api/v0/ssh/enabled", body); w.Code != http.StatusOK {
			t.Fatalf("PUT enabled %s = %d: %s", body, w.Code, w.Body.String())
		}
		want := []string{"sudo", "-n", sshutil.HelperPath, action, "stdin="}
		if len(*h.calls) != 1 || !slices.Equal((*h.calls)[0], want) {
			t.Errorf("PUT enabled %s ran %v, want %v", body, *h.calls, want)
		}
	}
	if w := h.do(http.MethodPut, "/api/v0/ssh/enabled", `{}`); w.Code != http.StatusBadRequest {
		t.Errorf("PUT enabled without a value = %d, want 400", w.Code)
	}

	line, fingerprint := publicKeyLine(t)
	w := h.do(http.MethodPost, "/api/v0/ssh/keys", jsonBody(t, map[string]string{"key": line}))
	if w.Code != http.StatusCreated {
		t.Fatalf("POST key = %d: %s", w.Code, w.Body.String())
	}
	var added sshutil.Key
	if err := json.Unmarshal(w.Body.Bytes(), &added); err != nil {
		t.Fatal(err)
	}
	if added.Fingerprint != fingerprint || added.Comment != "admin@laptop" {
		t.Errorf("added = %+v", added)
	}
	if w := h.do(http.MethodPost, "/api/v0/ssh/keys", jsonBody(t, map[string]string{"key": line})); w.Code != http.StatusConflict {
		t.Errorf("POST the same key = %d, want 409", w.Code)
	}
	if w := h.do(http.MethodPost, "/api/v0/ssh/keys", `{"key":"not a key"}`); w.Code != http.StatusBadRequest {
		t.Errorf("POST garbage = %d, want 400", w.Code)
	}
	if got := h.status(t); len(got.Keys) != 1 || got.Keys[0].Fingerprint != fingerprint {
		t.Errorf("keys = %+v", got.Keys)
	}

	removePath := "/api/v0/ssh/keys?fingerprint=" + url.QueryEscape(fingerprint)
	if w := h.do(http.MethodDelete, removePath, ""); w.Code != http.StatusOK {
		t.Fatalf("DELETE key = %d: %s", w.Code, w.Body.String())
	}
	if w := h.do(http.MethodDelete, removePath, ""); w.Code != http.StatusNotFound {
		t.Errorf("DELETE it again = %d, want 404", w.Code)
	}
	if w := h.do(http.MethodDelete, "/api/v0/ssh/keys", ""); w.Code != http.StatusBadRequest {
		t.Errorf("DELETE without a fingerprint = %d, want 400", w.Code)
	}

	*h.calls = nil
	const password = "a long enough password"
	if w := h.do(http.MethodPut, "/api/v0/ssh/password", jsonBody(t, map[string]string{"password": password})); w.Code != http.StatusOK {
		t.Fatalf("PUT password = %d: %s", w.Code, w.Body.String())
	}
	if w := h.do(http.MethodPut, "/api/v0/ssh/password", `{"password":"short"}`); w.Code != http.StatusBadRequest {
		t.Errorf("PUT a short password = %d, want 400", w.Code)
	}
	if w := h.do(http.MethodDelete, "/api/v0/ssh/password", ""); w.Code != http.StatusOK {
		t.Fatalf("DELETE password = %d: %s", w.Code, w.Body.String())
	}
	want := [][]string{
		{"sudo", "-n", sshutil.HelperPath, "set-password", "stdin=" + password + "\n"},
		{"sudo", "-n", sshutil.HelperPath, "clear-password", "stdin="},
	}
	if !slices.EqualFunc(*h.calls, want, slices.Equal) {
		t.Errorf("password calls = %q, want %q", *h.calls, want)
	}
}

// TestSSH_Unavailable reports why and refuses every change with 409, running
// nothing.
func TestSSH_Unavailable(t *testing.T) {
	h := newSSHHarness(t, sshutil.ReasonHelperMissing)

	if got := h.status(t); got.Available || got.Reason != string(sshutil.ReasonHelperMissing) {
		t.Errorf("status = %+v, want unavailable with reason helper_missing", got)
	}
	line, fingerprint := publicKeyLine(t)
	for _, r := range []struct{ method, path, body string }{
		{http.MethodPut, "/api/v0/ssh/enabled", `{"enabled":true}`},
		{http.MethodPost, "/api/v0/ssh/keys", jsonBody(t, map[string]string{"key": line})},
		{http.MethodDelete, "/api/v0/ssh/keys?fingerprint=" + url.QueryEscape(fingerprint), ""},
		{http.MethodPut, "/api/v0/ssh/password", `{"password":"a long enough password"}`},
		{http.MethodDelete, "/api/v0/ssh/password", ""},
	} {
		if w := h.do(r.method, r.path, r.body); w.Code != http.StatusConflict {
			t.Errorf("%s %s = %d, want 409", r.method, r.path, w.Code)
		}
	}
	if len(*h.calls) != 0 {
		t.Errorf("an unavailable host ran %v", *h.calls)
	}
}
