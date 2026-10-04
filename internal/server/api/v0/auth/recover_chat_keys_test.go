package v0_auth_test

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
)

// TestRecover_ChatKeys drives the two recovery requests of #2416: fetch the
// wrapped keys with the recovery key, then reset the password and store the
// re-wrapped keys in one request, which rolls back together.
func TestRecover_ChatKeys(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	if _, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "admin", AuthKey: dbtest.AuthKey("admin-password"), SaltSecret: dbtest.SaltSecret}); err != nil {
		t.Fatal(err)
	}
	const phrase = "apple-bread-cloud-delta-eagle-flame"
	createRecoverableUser(t, database.Queries, "bob", phrase)
	bob, err := database.Queries.GetUserByUsername(ctx, "bob")
	if err != nil {
		t.Fatal(err)
	}

	engine := newPublicAuthEngine(t, database)
	post := func(path string, body any) *httptest.ResponseRecorder {
		encoded, _ := json.Marshal(body)
		req := httptest.NewRequest(http.MethodPost, "/api/v0"+path, bytes.NewReader(encoded))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		engine.ServeHTTP(w, req)
		return w
	}
	keys := func(fill byte) chatutil.Keys {
		b := func(n int) []byte { return bytes.Repeat([]byte{fill}, n) }
		return chatutil.Keys{
			BoxPublicKey: b(32), SignPublicKey: b(32),
			WrappedByPassword: b(104), SaltPw: b(16),
			WrappedByPhrase: b(104), SaltRp: b(16),
			KdfParams: json.RawMessage(`{"alg":"argon2id13","opsLimit":3,"memLimit":67108864}`),
		}
	}
	fetch := map[string]string{"username": "bob", "recoveryKey": dbtest.AuthKey(phrase)}

	if w := post("/auth/recover/keys", fetch); w.Code != http.StatusNotFound {
		t.Fatalf("fetch before bob has keys = %d %s, want 404", w.Code, w.Body)
	}
	if _, err := chatutil.PutKeys(chatutil.PutKeysParams{Ctx: ctx, Queries: database.Queries, UserID: bob.ID, Keys: keys(1)}); err != nil {
		t.Fatal(err)
	}
	if w := post("/auth/recover/keys", map[string]string{"username": "bob", "recoveryKey": dbtest.AuthKey("wrong-phrase")}); w.Code != http.StatusBadRequest {
		t.Errorf("fetch with a wrong phrase = %d, want 400", w.Code)
	}
	w := post("/auth/recover/keys", fetch)
	if w.Code != http.StatusOK {
		t.Fatalf("fetch = %d %s, want 200", w.Code, w.Body)
	}
	var fetched map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &fetched)
	if fetched["wrappedByPhrase"] != base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{1}, 104)) {
		t.Errorf("fetched = %v, want bob's phrase wrap", fetched)
	}

	// Malformed keys refuse the whole recovery: the old password still works.
	bad := keys(2)
	bad.SaltPw = nil
	if w := post("/auth/recover", map[string]any{"username": "bob", "recoveryKey": dbtest.AuthKey(phrase), "newAuthKey": dbtest.AuthKey("brand-new-password"), "chatKeys": bad}); w.Code != http.StatusBadRequest {
		t.Fatalf("recover with malformed keys = %d %s, want 400", w.Code, w.Body)
	}
	if _, err := authutil.Login(ctx, database.Queries, authutil.LoginParams{Username: "bob", AuthKey: dbtest.AuthKey("brand-new-password")}); err == nil {
		t.Error("a refused recovery changed the password")
	}

	w = post("/auth/recover", map[string]any{"username": "bob", "recoveryKey": dbtest.AuthKey(phrase), "newAuthKey": dbtest.AuthKey("brand-new-password"), "chatKeys": keys(3)})
	if w.Code != http.StatusOK {
		t.Fatalf("recover = %d %s, want 200", w.Code, w.Body)
	}
	got, err := chatutil.GetKeys(chatutil.GetKeysParams{Ctx: ctx, Queries: database.Queries, UserID: bob.ID})
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got.Keys.WrappedByPassword, bytes.Repeat([]byte{3}, 104)) {
		t.Errorf("recover didn't store the re-wrapped keys: %v", got.Keys.WrappedByPassword)
	}

	// Recovering without chatKeys leaves them alone.
	if w := post("/auth/recover", map[string]any{"username": "bob", "recoveryKey": dbtest.AuthKey(phrase), "newAuthKey": dbtest.AuthKey("another-password")}); w.Code != http.StatusOK {
		t.Fatalf("recover without keys = %d %s", w.Code, w.Body)
	}
	if again, _ := chatutil.GetKeys(chatutil.GetKeysParams{Ctx: ctx, Queries: database.Queries, UserID: bob.ID}); !bytes.Equal(again.Keys.WrappedByPassword, got.Keys.WrappedByPassword) {
		t.Error("recover without chatKeys changed the stored keys")
	}

	if w := post("/auth/recover", map[string]any{"username": "bob", "recoveryKey": dbtest.AuthKey(phrase), "newAuthKey": strings.Repeat("p", 9<<10)}); w.Code != http.StatusBadRequest {
		t.Errorf("recover with a 9 KiB body = %d, want 400", w.Code)
	}
}
