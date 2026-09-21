package v0_files_test

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"maps"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// A member's home, users/<username>, carries their owner grant. Trashing or
// moving it strands the account and lets RepairHomes create an empty home in
// its place at the next restart (#2016).

// fakeUsb is a USB device that only knows its serial.
type fakeUsb struct {
	storageutil.UsbDevice
	serial string
}

func (u fakeUsb) GetSerial() string { return u.serial }

func newHomeHarness(t *testing.T, admin bool) accessHarness {
	t.Helper()
	h := newAccessHarness(t, admin)
	writeFixture(t, h.filesDir, "users/bob/notes.txt")
	writeFixture(t, h.filesDir, "users/bob/sub/deep.txt")
	h.grant(t, "users/bob", accessutil.Owner)
	return h
}

func (h accessHarness) delMany(serial, rootDir string, names ...string) *httptest.ResponseRecorder {
	q := url.Values{"rootDir": {rootDir}, "filePaths": names, "serial": {serial}}
	return doRequest(h.engine, http.MethodDelete, "/api/v0/files?"+q.Encode(), nil, "")
}

func (h accessHarness) moveOn(serial, oldPath, newPath string) *httptest.ResponseRecorder {
	body, _ := json.Marshal(map[string]string{
		"oldFilePath": oldPath, "newFilePath": newPath,
		"oldDeviceSerial": serial, "newDeviceSerial": serial,
	})
	return doRequest(h.engine, http.MethodPut, "/api/v0/files", bytes.NewReader(body), "application/json")
}

func TestHome_MemberCannotDeleteOrMoveTheirHome(t *testing.T) {
	h := newHomeHarness(t, false)
	writeFixture(t, h.filesDir, "shared/x.txt")
	h.grant(t, "shared", accessutil.Write)
	before := h.levels(t)

	expectCodes(t, http.StatusForbidden, map[string]*httptest.ResponseRecorder{
		"delete":                  h.del("users", "bob"),
		"delete, full path":       h.del("", "users/bob"),
		"delete, unclean":         h.del("", "/users/./bob/"),
		"batch with home":         h.delMany("", "", "users/bob/notes.txt", "users/bob"),
		"rename":                  h.move("users/bob", "users/bobby"),
		"move into a write share": h.move("users/bob", "shared/bob"),
	})

	expectExists(t, h.filesDir, "users/bob/notes.txt", "users/bob/sub/deep.txt")
	if _, err := os.Stat(filepath.Join(h.filesDir, "shared", "bob")); !os.IsNotExist(err) {
		t.Errorf("the home was moved into shared: %v", err)
	}
	if got := h.levels(t); !maps.Equal(got, before) {
		t.Errorf("rows = %v, want them untouched: %v", got, before)
	}
}

func TestHome_MemberManagesWhatIsInsideTheirHome(t *testing.T) {
	h := newHomeHarness(t, false)

	if w := h.move("users/bob/notes.txt", "users/bob/renamed.txt"); w.Code != http.StatusOK {
		t.Fatalf("rename a file = %d: %s", w.Code, w.Body.String())
	}
	if w := h.move("users/bob/sub", "users/bob/moved"); w.Code != http.StatusOK {
		t.Fatalf("rename a folder = %d: %s", w.Code, w.Body.String())
	}
	if w := h.move("users/bob/renamed.txt", "users/bob/moved/renamed.txt"); w.Code != http.StatusOK {
		t.Fatalf("move a file into a subfolder = %d: %s", w.Code, w.Body.String())
	}
	expectExists(t, h.filesDir, "users/bob/moved/deep.txt", "users/bob/moved/renamed.txt")

	if w := h.delMany("", "users/bob", "moved/renamed.txt", "moved"); w.Code != http.StatusOK {
		t.Fatalf("delete inside the home = %d: %s", w.Code, w.Body.String())
	}
	if _, err := os.Stat(filepath.Join(h.filesDir, "users", "bob", "moved")); !os.IsNotExist(err) {
		t.Errorf("users/bob/moved still exists after delete: %v", err)
	}
	expectExists(t, h.filesDir, "users/bob")
	if got := h.levels(t)["users/bob"]; got != "owner" {
		t.Errorf("home grant = %q, want owner", got)
	}
}

func TestHome_AdminCanDeleteAHome(t *testing.T) {
	h := newHomeHarness(t, true)

	if w := h.del("users", "bob"); w.Code != http.StatusOK {
		t.Fatalf("admin delete = %d: %s", w.Code, w.Body.String())
	}
	if _, err := os.Stat(filepath.Join(h.filesDir, "users", "bob")); !os.IsNotExist(err) {
		t.Errorf("users/bob still exists after an admin delete: %v", err)
	}
}

func TestHome_UsersFolderOnAnotherDeviceIsNotAHome(t *testing.T) {
	usbMount := t.TempDir()
	h := newAccessHarness(t, false, storageutil.Device{
		Name: "USB", MountPoint: usbMount, UsbInfo: fakeUsb{serial: "USB1"},
	})
	usbFiles := filepath.Join(usbMount, "quark", "data", "files")
	writeFixture(t, usbFiles, "users/bob/a.txt")
	writeFixture(t, usbFiles, "users/carl/b.txt")
	if err := h.database.Queries.SetUserPathAccess(context.Background(), db.SetUserPathAccessParams{
		DeviceSerial: "USB1",
		RelPath:      "users",
		UserID:       sql.NullInt64{Int64: h.userID, Valid: true},
		Level:        accessutil.Owner.String(),
	}); err != nil {
		t.Fatal(err)
	}

	if w := h.moveOn("USB1", "users/bob", "users/robert"); w.Code != http.StatusOK {
		t.Errorf("rename users/bob on a USB drive = %d: %s", w.Code, w.Body.String())
	}
	if w := h.delMany("USB1", "users", "carl"); w.Code != http.StatusOK {
		t.Errorf("delete users/carl on a USB drive = %d: %s", w.Code, w.Body.String())
	}
	expectExists(t, usbFiles, "users/robert/a.txt")
}
