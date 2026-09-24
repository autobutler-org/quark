package provisionutil

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/settingsutil"
)

func TestProvisionAuthKey_ReturnsKey(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/provision" {
			t.Errorf("got %s %s; want POST /provision", r.Method, r.URL.Path)
		}
		if got := r.Header.Get("X-Provisioning-Secret"); got != "" {
			t.Errorf("X-Provisioning-Secret = %q; want no secret header (#1879)", got)
		}
		var req provisionRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.DeviceID != "device-abc" {
			t.Errorf("body = %+v, %v; want device_id device-abc", req, err)
		}
		_ = json.NewEncoder(w).Encode(provisionResponse{AuthKey: "hskey-auth-12345"})
	}))
	defer ts.Close()

	got, err := ProvisionAuthKey(ProvisionAuthKeyParams{
		URL:      ts.URL + "/provision",
		DeviceID: "device-abc",
	})
	if err != nil {
		t.Fatalf("ProvisionAuthKey: %v", err)
	}
	if got.AuthKey != "hskey-auth-12345" {
		t.Errorf("AuthKey = %q; want hskey-auth-12345", got.AuthKey)
	}
}

func TestProvisionAuthKey_Failures(t *testing.T) {
	cases := []struct {
		name    string
		handler http.HandlerFunc
	}{
		{"non-200", func(w http.ResponseWriter, _ *http.Request) {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
		}},
		{"empty key", func(w http.ResponseWriter, _ *http.Request) {
			_ = json.NewEncoder(w).Encode(provisionResponse{})
		}},
		{"oversized body", func(w http.ResponseWriter, _ *http.Request) {
			_, _ = w.Write([]byte(`{"auth_key":"` + strings.Repeat("a", maxResponseBytes) + `"}`))
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ts := httptest.NewServer(tc.handler)
			defer ts.Close()
			if _, err := ProvisionAuthKey(ProvisionAuthKeyParams{URL: ts.URL, DeviceID: "d"}); err == nil {
				t.Fatal("ProvisionAuthKey() = nil error; want one")
			}
		})
	}
}

func TestProvisioningURL(t *testing.T) {
	t.Setenv("QUARK_PROVISIONING_URL", "")
	if got := provisioningURL(); got != defaultProvisioningURL {
		t.Errorf("default = %q; want %q", got, defaultProvisioningURL)
	}
	t.Setenv("QUARK_PROVISIONING_URL", "https://example.test/provision")
	if got := provisioningURL(); got != "https://example.test/provision" {
		t.Errorf("override = %q; want the env value", got)
	}
}

func TestDefaultDeviceID_StableSha256(t *testing.T) {
	a, b := defaultDeviceID(), defaultDeviceID()
	if a != b || len(a) != 64 {
		t.Errorf("defaultDeviceID() = %q then %q; want one stable 64-char hex digest", a, b)
	}
}

// TestEnroll_StoresAndReusesHousehold verifies the first enrollment stores
// the household credential the service returns, in a 0600 settings file, and
// that the next one (after Disable, then Enable) presents it instead of
// creating a new household (#2358).
func TestEnroll_StoresAndReusesHousehold(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	settingsutil.ResetForTesting(path)
	var seen []provisionRequest
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req provisionRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Errorf("decode request: %v", err)
		}
		seen = append(seen, req)
		_ = json.NewEncoder(w).Encode(provisionResponse{
			AuthKey:        "hskey-auth-" + string(rune('a'+len(seen))),
			Household:      "household-abc",
			HouseholdToken: "token-abc",
		})
	}))
	defer ts.Close()
	t.Setenv("QUARK_PROVISIONING_URL", ts.URL+"/provision")

	first, err := Enroll()
	if err != nil || first.AuthKey != "hskey-auth-b" {
		t.Fatalf("first Enroll() = %+v, %v; want hskey-auth-b", first, err)
	}
	if seen[0].Household != "" || seen[0].HouseholdToken != "" || seen[0].DeviceID != DeviceID() {
		t.Errorf("first request = %+v; want a cold enrollment with this Quark's device ID", seen[0])
	}
	if h, tok := settingsutil.GetHousehold(); h != "household-abc" || tok != "token-abc" {
		t.Errorf("stored credential = %q, %q; want the service's", h, tok)
	}
	info, err := os.Stat(path)
	if err != nil || info.Mode().Perm() != 0o600 {
		t.Errorf("settings file mode = %v, %v; want 0600", info, err)
	}

	// A restart reads the credential from disk.
	settingsutil.ResetForTesting(path)
	if _, err := Enroll(); err != nil {
		t.Fatalf("second Enroll() = %v", err)
	}
	if seen[1].Household != "household-abc" || seen[1].HouseholdToken != "token-abc" {
		t.Errorf("second request = %+v; want the stored household credential", seen[1])
	}
}

func TestProvisionAuthKey_SendsAndReturnsHousehold(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req provisionRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Household != "hh" || req.HouseholdToken != "tok" {
			t.Errorf("body = %+v, %v; want household hh and token tok", req, err)
		}
		_ = json.NewEncoder(w).Encode(provisionResponse{AuthKey: "k", Household: "hh", HouseholdToken: "tok"})
	}))
	defer ts.Close()

	got, err := ProvisionAuthKey(ProvisionAuthKeyParams{URL: ts.URL, DeviceID: "phone", Household: "hh", HouseholdToken: "tok"})
	if err != nil || got != (ProvisionAuthKeyResult{AuthKey: "k", Household: "hh", HouseholdToken: "tok"}) {
		t.Errorf("ProvisionAuthKey() = %+v, %v; want the key and the household", got, err)
	}
}
