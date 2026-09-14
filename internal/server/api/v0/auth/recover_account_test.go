package v0_auth_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_auth "github.com/autobutler-org/quark/internal/server/api/v0/auth"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// TestRecoverAccount_NamedAccount drives POST /auth/recover against a Quark
// with two accounts. The phrase is checked against the account the request
// names, and an unknown username is indistinguishable from a wrong phrase.
func TestRecoverAccount_NamedAccount(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	founder, err := authutil.Setup(ctx, database.Queries, authutil.SetupParams{Username: "admin", Password: "admin-password"})
	if err != nil {
		t.Fatalf("authutil.Setup: %v", err)
	}
	const bobPhrase = "apple-bread-cloud-delta-eagle-flame"
	createRecoverableUser(t, database.Queries, "bob", bobPhrase)

	deps := deputil.NewDependencies().WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_auth.NewRouter())

	recoverAs := func(username, phrase string) *httptest.ResponseRecorder {
		body, _ := json.Marshal(map[string]string{
			"username":       username,
			"recoveryPhrase": phrase,
			"newPassword":    "brand-new-password",
		})
		req := httptest.NewRequest(http.MethodPost, "/api/v0/auth/recover", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		engine.ServeHTTP(w, req)
		return w
	}

	wrongUser := recoverAs("bob", founder.RecoveryPhrase)
	if wrongUser.Code != http.StatusBadRequest {
		t.Errorf("bob with admin's phrase = %d, want 400: %s", wrongUser.Code, wrongUser.Body.String())
	}
	unknownUser := recoverAs("nobody", founder.RecoveryPhrase)
	if unknownUser.Code != http.StatusBadRequest {
		t.Errorf("unknown user = %d, want 400: %s", unknownUser.Code, unknownUser.Body.String())
	}
	if unknownUser.Body.String() != wrongUser.Body.String() {
		t.Errorf("unknown user body %q differs from wrong phrase body %q", unknownUser.Body.String(), wrongUser.Body.String())
	}

	rightUser := recoverAs("bob", bobPhrase)
	if rightUser.Code != http.StatusOK {
		t.Fatalf("bob with bob's phrase = %d, want 200: %s", rightUser.Code, rightUser.Body.String())
	}
	if _, err := authutil.Login(ctx, database.Queries, authutil.LoginParams{Username: "bob", Password: "brand-new-password"}); err != nil {
		t.Errorf("bob should log in with the new password: %v", err)
	}
	if _, err := authutil.Login(ctx, database.Queries, authutil.LoginParams{Username: "admin", Password: "admin-password"}); err != nil {
		t.Errorf("admin's password must be untouched: %v", err)
	}
}

func createRecoverableUser(t *testing.T, queries *db.Queries, username, phrase string) {
	t.Helper()
	passwordHash, err := authutil.HashPassword("original-password")
	if err != nil {
		t.Fatal(err)
	}
	phraseHash, err := authutil.HashPassword(authutil.NormalizeRecoveryPhrase(phrase))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := queries.CreateUser(context.Background(), db.CreateUserParams{
		Username:           username,
		PasswordHash:       passwordHash,
		RecoveryPhraseHash: phraseHash,
	}); err != nil {
		t.Fatal(err)
	}
}
