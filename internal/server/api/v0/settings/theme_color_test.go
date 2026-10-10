package v0_settings_test

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/autobutler-org/quark/pkg/util/usersettingsutil"
)

// themeColorOf decodes a response body and returns its theme color, failing unless the
// body is exactly {"themeColor": <string>}.
func themeColorOf(t *testing.T, body []byte) string {
	t.Helper()
	var got map[string]any
	if err := json.Unmarshal(body, &got); err != nil {
		t.Fatalf("decode %s: %v", body, err)
	}
	themeColor, ok := got["themeColor"].(string)
	if !ok || len(got) != 1 {
		t.Fatalf(`body = %s; want exactly {"themeColor": "<string>"}`, body)
	}
	return themeColor
}

// userSettings returns what the user_settings table holds, as "<user
// id>:<theme color>" for each row in id order, joined by spaces.
func (h featuresHarness) userSettings(t *testing.T) string {
	t.Helper()
	rows, err := h.database.Db.Query(`SELECT user_id, settings FROM user_settings ORDER BY user_id`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var held []string
	for rows.Next() {
		var id, settings string
		if err := rows.Scan(&id, &settings); err != nil {
			t.Fatal(err)
		}
		held = append(held, id+":"+themeColorOf(t, []byte(settings)))
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	return strings.Join(held, " ")
}

// publishedPublicSettings counts the public_settings_changed events so far.
func (h featuresHarness) publishedPublicSettings() int {
	n := 0
	for {
		select {
		case evt := <-h.events:
			if evt.Kind == eventbus.EventPublicSettingsChanged {
				n++
			}
		default:
			return n
		}
	}
}

// TestGetPublicSettings_ExactKeys pins the public response to its allowlist:
// theme color and nothing else, whatever settings.json holds. The route needs no
// session, so a key added here by accident is disclosed to anyone on the
// network.
func TestGetPublicSettings_ExactKeys(t *testing.T) {
	h := newFeaturesHarness(t)
	if err := settingsutil.SetHousehold("household", "household-token"); err != nil {
		t.Fatal(err)
	}
	if err := settingsutil.SetDeviceID("device-id"); err != nil {
		t.Fatal(err)
	}

	w := h.do("", http.MethodGet, "/api/v0/settings/public", "")
	if w.Code != http.StatusOK {
		t.Fatalf("GET = %d: %s", w.Code, w.Body.String())
	}
	if got := themeColorOf(t, w.Body.Bytes()); got != "" {
		t.Errorf("theme color before an admin chose = %q, want empty", got)
	}
	for _, secret := range []string{"household", "device-id", "Token"} {
		if strings.Contains(w.Body.String(), secret) {
			t.Errorf("public settings disclose %q: %s", secret, w.Body.String())
		}
	}

	if err := settingsutil.SetThemeColor("teal"); err != nil {
		t.Fatal(err)
	}
	w = h.do("", http.MethodGet, "/api/v0/settings/public", "")
	if got := themeColorOf(t, w.Body.Bytes()); got != "teal" {
		t.Errorf("theme color = %q, want teal", got)
	}
}

// TestUpdateThemeColor_AdminPersistsAndPublishes checks an admin's PUT is stored,
// survives a reload, is what the public route then reports, tells open apps
// once per change, and clears with the empty string.
func TestUpdateThemeColor_AdminPersistsAndPublishes(t *testing.T) {
	h := newFeaturesHarness(t)
	for _, themeColor := range []string{"teal", "#0ea5e9", ""} {
		body, _ := json.Marshal(map[string]string{"themeColor": themeColor})
		w := h.do("admin", http.MethodPut, "/api/v0/settings/theme-color", string(body))
		if w.Code != http.StatusOK {
			t.Fatalf("PUT %q = %d: %s", themeColor, w.Code, w.Body.String())
		}
		if got := themeColorOf(t, w.Body.Bytes()); got != themeColor {
			t.Errorf("PUT %q answered %q", themeColor, got)
		}
		if n := h.publishedPublicSettings(); n != 1 {
			t.Errorf("PUT %q published %d public_settings_changed events; want 1", themeColor, n)
		}
		settingsutil.ResetForTesting(h.path)
		if got := themeColorOf(t, h.do("", http.MethodGet, "/api/v0/settings/public", "").Body.Bytes()); got != themeColor {
			t.Errorf("public theme color after PUT %q and a reload = %q", themeColor, got)
		}
	}
}

// TestUpdateThemeColor_Refusals checks a member is forbidden, a caller with no
// session is a 401, and a malformed or
// missing themeColor is a 400; none of them changes the theme color or publishes.
func TestUpdateThemeColor_Refusals(t *testing.T) {
	h := newFeaturesHarness(t)
	if err := settingsutil.SetThemeColor("teal"); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, user, body string
		want             int
	}{
		{"member", "member", `{"themeColor":"red"}`, http.StatusForbidden},
		{"nobody", "", `{"themeColor":"red"}`, http.StatusUnauthorized},
		{"no theme color", "admin", `{}`, http.StatusBadRequest},
		{"null theme color", "admin", `{"themeColor":null}`, http.StatusBadRequest},
		{"uppercase color", "admin", `{"themeColor":"#0EA5E9"}`, http.StatusBadRequest},
		{"short color", "admin", `{"themeColor":"#0ea"}`, http.StatusBadRequest},
		{"uppercase name", "admin", `{"themeColor":"Teal"}`, http.StatusBadRequest},
		{"long name", "admin", `{"themeColor":"a` + strings.Repeat("b", 32) + `"}`, http.StatusBadRequest},
		{"not a string", "admin", `{"themeColor":7}`, http.StatusBadRequest},
		{"oversized", "admin", `{"themeColor":"` + strings.Repeat("a", int(usersettingsutil.MaxRequestBytes)) + `"}`, http.StatusBadRequest},
	} {
		if w := h.do(tc.user, http.MethodPut, "/api/v0/settings/theme-color", tc.body); w.Code != tc.want {
			t.Errorf("%s: PUT = %d, want %d: %s", tc.name, w.Code, tc.want, w.Body.String())
		}
	}
	if got := settingsutil.GetThemeColor(); got != "teal" {
		t.Errorf("a refused PUT changed the theme color to %q", got)
	}
	if n := h.publishedPublicSettings(); n != 0 {
		t.Errorf("refused PUTs published %d events", n)
	}
}

// TestMySettings_OwnAccountOnly checks each account reads and writes only its
// own row: the id comes from the session, so nothing a caller sends can name
// another account. It also checks an account that has chosen nothing follows
// the Quark, and that an override publishes no event.
func TestMySettings_OwnAccountOnly(t *testing.T) {
	h := newFeaturesHarness(t)
	for _, user := range []string{"admin", "member"} {
		w := h.do(user, http.MethodGet, "/api/v0/settings/me", "")
		if w.Code != http.StatusOK {
			t.Fatalf("GET as %s = %d: %s", user, w.Code, w.Body.String())
		}
		if got := themeColorOf(t, w.Body.Bytes()); got != "" {
			t.Errorf("%s's theme color before choosing = %q, want empty", user, got)
		}
	}

	w := h.do("member", http.MethodPut, "/api/v0/settings/me", `{"themeColor":"teal"}`)
	if w.Code != http.StatusOK || themeColorOf(t, w.Body.Bytes()) != "teal" {
		t.Fatalf("PUT as member = %d: %s", w.Code, w.Body.String())
	}
	if got := themeColorOf(t, h.do("member", http.MethodGet, "/api/v0/settings/me", "").Body.Bytes()); got != "teal" {
		t.Errorf("member's theme color = %q, want teal", got)
	}
	if got := themeColorOf(t, h.do("admin", http.MethodGet, "/api/v0/settings/me", "").Body.Bytes()); got != "" {
		t.Errorf("admin reads %q after the member chose; want their own, empty", got)
	}

	// A caller cannot aim a write at another account: an id in the query is
	// ignored and one in the body is an unknown field.
	adminID, memberID := h.userID(t, "admin"), h.userID(t, "member")
	target := "/api/v0/settings/me?userId=" + memberID + "&user_id=" + memberID
	if w := h.do("admin", http.MethodPut, target, `{"themeColor":"#112233"}`); w.Code != http.StatusOK {
		t.Fatalf("PUT as admin = %d: %s", w.Code, w.Body.String())
	}
	if w := h.do("admin", http.MethodPut, "/api/v0/settings/me", `{"themeColor":"red","userId":`+memberID+`}`); w.Code != http.StatusBadRequest {
		t.Errorf("PUT naming another account in the body = %d, want 400", w.Code)
	}
	if got := themeColorOf(t, h.do("member", http.MethodGet, "/api/v0/settings/me", "").Body.Bytes()); got != "teal" {
		t.Errorf("member's theme color after the admin's writes = %q, want teal", got)
	}
	if got := themeColorOf(t, h.do("admin", http.MethodGet, target, "").Body.Bytes()); got != "#112233" {
		t.Errorf("admin's theme color = %q, want #112233", got)
	}

	if got := h.userSettings(t); got != adminID+":#112233 "+memberID+":teal" {
		t.Errorf("user_settings holds %q; want #112233 for %s and teal for %s", got, adminID, memberID)
	}
	if n := h.publishedPublicSettings(); n != 0 {
		t.Errorf("user overrides published %d public_settings_changed events; want none", n)
	}
}

// TestMySettings_Refusals checks a caller with no session is a 401, and that
// an unknown field, a malformed theme color and an oversized body are each a 400
// that stores nothing.
func TestMySettings_Refusals(t *testing.T) {
	h := newFeaturesHarness(t)
	for _, method := range []string{http.MethodGet, http.MethodPut} {
		if w := h.do("", method, "/api/v0/settings/me", `{"themeColor":"teal"}`); w.Code != http.StatusUnauthorized {
			t.Errorf("%s with no session = %d, want 401", method, w.Code)
		}
	}
	for name, body := range map[string]string{
		"unknown field":   `{"themeColor":"teal","theme":"dark"}`,
		"uppercase color": `{"themeColor":"#0EA5E9"}`,
		"css color":       `{"themeColor":"rgb(1,2,3)"}`,
		"not a string":    `{"themeColor":7}`,
		"not JSON":        `themeColor=teal`,
		"empty":           ``,
		"oversized":       `{"themeColor":"` + strings.Repeat("a", int(usersettingsutil.MaxRequestBytes)) + `"}`,
	} {
		if w := h.do("member", http.MethodPut, "/api/v0/settings/me", body); w.Code != http.StatusBadRequest {
			t.Errorf("%s: PUT = %d, want 400: %s", name, w.Code, w.Body.String())
		}
	}
	if got := h.userSettings(t); got != "" {
		t.Errorf("a refused PUT stored %q", got)
	}
}
