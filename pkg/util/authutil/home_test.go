package authutil_test

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// homeOf is the path an account's home sits at under filesDir.
func homeOf(filesDir, username string) string {
	return filepath.Join(filesDir, "users", username)
}

// ownsHome reports whether the account may write to its own home, which is the
// question every upload asks (#1908).
func ownsHome(t *testing.T, f createUserFixture, userID int64, username string) bool {
	t.Helper()
	loaded, err := accessutil.Load(accessutil.LoadParams{
		Ctx:       context.Background(),
		Database:  f.database,
		Storage:   f.storage,
		Principal: accessutil.Principal{UserID: userID},
	})
	if err != nil {
		t.Fatal(err)
	}
	return loaded.Access.Check("", "users/"+username+"/notes.txt", accessutil.Write).Allowed
}

// addAccountWithoutHome inserts an active account straight into the table, the
// way an approval did before it made homes: a row, and nothing else.
func addAccountWithoutHome(t *testing.T, f createUserFixture, username string) int64 {
	t.Helper()
	hash, err := authutil.HashPassword("user-password")
	if err != nil {
		t.Fatal(err)
	}
	user, err := f.database.Queries.CreateUser(context.Background(), db.CreateUserParams{
		Username:           username,
		PasswordHash:       hash,
		RecoveryPhraseHash: hash,
	})
	if err != nil {
		t.Fatal(err)
	}
	return user.ID
}

func repair(t *testing.T, f createUserFixture) authutil.RepairHomesResult {
	t.Helper()
	result, err := authutil.RepairHomes(context.Background(), authutil.RepairHomesParams{
		Database: f.database,
		FilesDir: f.filesDir,
	})
	if err != nil {
		t.Fatalf("RepairHomes: %v", err)
	}
	return result
}

// TestApproveRequest_MakesTheHomeAndItsGrant checks approval gives the account
// the home an upload needs. Approval used to flip the status and nothing else,
// which left an active account owning no path at all, so every upload it tried
// was refused (#1908).
func TestApproveRequest_MakesTheHomeAndItsGrant(t *testing.T) {
	f := newCreateUserFixture(t)
	ctx := context.Background()

	if _, err := request(f.database.Queries, "bob", "bob-password"); err != nil {
		t.Fatal(err)
	}
	result, err := authutil.ApproveRequest(ctx, authutil.ApproveRequestParams{
		Database: f.database,
		Username: "bob",
		FilesDir: f.filesDir,
	})
	if err != nil {
		t.Fatalf("approve: %v", err)
	}

	if result.FolderPath != "users/bob" {
		t.Errorf("FolderPath = %q, want users/bob", result.FolderPath)
	}
	if info, err := os.Stat(homeOf(f.filesDir, "bob")); err != nil || !info.IsDir() {
		t.Fatalf("home of an approved account: %v", err)
	}
	bob, err := f.database.Queries.GetUserByUsername(ctx, "bob")
	if err != nil {
		t.Fatal(err)
	}
	if bob.Status != authutil.StatusActive {
		t.Errorf("approved account status = %q, want active", bob.Status)
	}
	if !ownsHome(t, f, bob.ID, "bob") {
		t.Error("an approved account cannot write to its own home, so every upload it tries is refused")
	}
	if _, err := authutil.Login(ctx, f.database.Queries, authutil.LoginParams{Username: "bob", Password: "bob-password"}); err != nil {
		t.Errorf("login after approval: %v", err)
	}
}

// seedHome makes users/<username> under filesDir with a file in it, the way an
// admin fills a home before the account exists, and returns the file's path.
func seedHome(t *testing.T, filesDir, username string) string {
	t.Helper()
	if err := os.MkdirAll(homeOf(filesDir, username), 0o755); err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(homeOf(filesDir, username), "photo.jpg")
	if err := os.WriteFile(file, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	return file
}

// TestNewAccounts_AdoptAnExistingHome checks that a folder already at
// users/<username> does not block setup, an admin's create, or an approval:
// the users table decides whether a name is taken, and the account takes over
// the folder with its contents intact.
func TestNewAccounts_AdoptAnExistingHome(t *testing.T) {
	ctx := context.Background()
	var seeded string
	f := newCreateUserFixtureWith(t, func(filesDir string) {
		seeded = seedHome(t, filesDir, "admin")
	})
	admin, err := f.database.Queries.GetUserByUsername(ctx, "admin")
	if err != nil {
		t.Fatal(err)
	}

	carolFile := seedHome(t, f.filesDir, "carol")
	carol, err := f.create("carol")
	if err != nil {
		t.Fatalf("create onto an existing home: %v", err)
	}
	if carol.FolderPath != "users/carol" {
		t.Errorf("FolderPath = %q, want users/carol", carol.FolderPath)
	}

	bobFile := seedHome(t, f.filesDir, "bob")
	if _, err := request(f.database.Queries, "bob", "bob-password"); err != nil {
		t.Fatal(err)
	}
	if _, err := authutil.ApproveRequest(ctx, authutil.ApproveRequestParams{
		Database: f.database,
		Username: "bob",
		FilesDir: f.filesDir,
	}); err != nil {
		t.Fatalf("approve onto an existing home: %v", err)
	}
	bob, err := f.database.Queries.GetUserByUsername(ctx, "bob")
	if err != nil {
		t.Fatal(err)
	}

	for _, tc := range []struct {
		username, file string
		id             int64
	}{
		{"admin", seeded, admin.ID},
		{"carol", carolFile, carol.UserID},
		{"bob", bobFile, bob.ID},
	} {
		if _, err := os.Stat(tc.file); err != nil {
			t.Errorf("%s: the adopted home lost its contents: %v", tc.username, err)
		}
		if !ownsHome(t, f, tc.id, tc.username) {
			t.Errorf("%s does not own the home it adopted", tc.username)
		}
	}
}

// TestCreateUser_NonFolderHomeLeavesItAlone checks a file sitting where the
// home would go fails the create with no account, and the file stays.
func TestCreateUser_NonFolderHomeLeavesItAlone(t *testing.T) {
	f := newCreateUserFixture(t)
	file := homeOf(f.filesDir, "bob")
	if err := os.WriteFile(file, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := f.create("bob"); err == nil {
		t.Fatal("create succeeded with a file where the home goes")
	}
	if _, err := f.database.Queries.GetUserByUsername(context.Background(), "bob"); err == nil {
		t.Error("a failed home left the account behind")
	}
	if info, err := os.Stat(file); err != nil || info.IsDir() {
		t.Errorf("the file in the way was touched: %v", err)
	}
}

// TestCreateUser_HomeThatCannotBeMadeLeavesNoAccount checks a home that cannot
// be made fails the create whole, with no account row and no directory left
// over. A users parent that is a file is the cheapest way to make the mkdir
// fail.
func TestCreateUser_HomeThatCannotBeMadeLeavesNoAccount(t *testing.T) {
	f := newCreateUserFixture(t)
	if err := os.RemoveAll(filepath.Join(f.filesDir, "users")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(f.filesDir, "users"), []byte("not a directory"), 0o644); err != nil {
		t.Fatal(err)
	}
	before := f.userCount(t)

	if _, err := f.create("bob"); err == nil {
		t.Fatal("create succeeded even though the home could not be made")
	}

	if after := f.userCount(t); after != before {
		t.Errorf("a failed home left %d accounts, want %d", after, before)
	}
	if _, err := f.database.Queries.GetUserByUsername(context.Background(), "bob"); err == nil {
		t.Error("a failed home left the account behind")
	}
	if info, err := os.Stat(filepath.Join(f.filesDir, "users")); err != nil || info.IsDir() {
		t.Errorf("users is %v, %v; the failed create should have left it alone", info, err)
	}
}

// TestRepairHomes_GivesEveryActiveAccountItsHome checks the startup repair on
// the two shapes a live Quark has: an account with neither directory nor grant,
// and one whose directory was made by hand but which owns nothing — the grant
// is what the access layer reads, so both are equally unusable. An admin is
// repaired too: admins bypass the table only while they are admins, and one can
// be demoted.
func TestRepairHomes_GivesEveryActiveAccountItsHome(t *testing.T) {
	f := newCreateUserFixture(t)
	ctx := context.Background()

	nothing := addAccountWithoutHome(t, f, "dee")
	byHand := addAccountWithoutHome(t, f, "hand")
	handMade := homeOf(f.filesDir, "hand")
	if err := os.MkdirAll(handMade, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(handMade, "photo.jpg"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	otherAdmin := addAccountWithoutHome(t, f, "cy")
	if err := authutil.PromoteToAdmin(ctx, f.database.Queries, "cy"); err != nil {
		t.Fatal(err)
	}

	result := repair(t, f)

	if got, want := len(result.Repaired), 3; got != want {
		t.Fatalf("repaired %v, want 3 accounts", result.Repaired)
	}
	for _, username := range []string{"dee", "hand", "cy"} {
		if info, err := os.Stat(homeOf(f.filesDir, username)); err != nil || !info.IsDir() {
			t.Errorf("home of %s: %v", username, err)
		}
	}
	if !ownsHome(t, f, nothing, "dee") {
		t.Error("an account with neither directory nor grant was not repaired")
	}
	if !ownsHome(t, f, byHand, "hand") {
		t.Error("an account whose home was made by hand still owns nothing")
	}
	if _, err := os.Stat(filepath.Join(handMade, "photo.jpg")); err != nil {
		t.Errorf("the repair emptied a home that was already there: %v", err)
	}
	// The admin's home is dormant while they are an admin and is what they are
	// left with the moment they are not.
	if err := authutil.DemoteFromAdmin(ctx, f.database.Queries, "cy"); err != nil {
		t.Fatal(err)
	}
	if !ownsHome(t, f, otherAdmin, "cy") {
		t.Error("a demoted admin cannot write to their own home")
	}
}

// TestRepairHomes_DoesNothingTwice checks the repair is idempotent, and leaves
// alone the accounts that should not have a home yet.
func TestRepairHomes_DoesNothingTwice(t *testing.T) {
	f := newCreateUserFixture(t)
	ctx := context.Background()
	if _, err := f.create("bob"); err != nil {
		t.Fatal(err)
	}
	if _, err := request(f.database.Queries, "waiting", "waiting-password"); err != nil {
		t.Fatal(err)
	}
	addAccountWithoutHome(t, f, "off")
	if _, err := f.database.Queries.SetUserStatus(ctx, db.SetUserStatusParams{
		Username:   "off",
		FromStatus: authutil.StatusActive,
		ToStatus:   authutil.StatusDisabled,
	}); err != nil {
		t.Fatal(err)
	}

	// Everything active already has its home, so the healthy Quark repairs
	// nothing — and a second pass over the repaired one repairs nothing either.
	if result := repair(t, f); len(result.Repaired) != 0 {
		t.Errorf("a healthy Quark repaired %v", result.Repaired)
	}
	if result := repair(t, f); len(result.Repaired) != 0 {
		t.Errorf("a second pass repaired %v", result.Repaired)
	}
	for _, username := range []string{"waiting", "off"} {
		if _, err := os.Stat(homeOf(f.filesDir, username)); !os.IsNotExist(err) {
			t.Errorf("%s is not an active account and should have no home: %v", username, err)
		}
	}
}

// TestSetup_FoundingAdminGetsAHome checks the founder is given a home like
// everyone else, and can still write to it once they are no longer an admin.
func TestSetup_FoundingAdminGetsAHome(t *testing.T) {
	f := newCreateUserFixture(t)
	ctx := context.Background()

	admin, err := f.database.Queries.GetUserByUsername(ctx, "admin")
	if err != nil {
		t.Fatal(err)
	}
	if info, err := os.Stat(homeOf(f.filesDir, "admin")); err != nil || !info.IsDir() {
		t.Fatalf("home of the founding admin: %v", err)
	}
	// Checked as a non-admin principal, because an admin is allowed everything
	// without a row and would pass whether the grant exists or not.
	if !ownsHome(t, f, admin.ID, "admin") {
		t.Error("the founding admin owns no home, so demoting them leaves them nowhere to write")
	}

	// And with the grant in place, demotion really does leave them usable.
	if _, err := f.create("second"); err != nil {
		t.Fatal(err)
	}
	if err := authutil.PromoteToAdmin(ctx, f.database.Queries, "second"); err != nil {
		t.Fatal(err)
	}
	if err := authutil.DemoteFromAdmin(ctx, f.database.Queries, "admin"); err != nil {
		t.Fatalf("demote the founder: %v", err)
	}
	if !ownsHome(t, f, admin.ID, "admin") {
		t.Error("a demoted founder cannot write to their own home")
	}
}
