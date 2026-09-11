package provisionutil

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestProvisionAuthKey_ReturnsKey(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/provision" {
			t.Errorf("got %s %s; want POST /provision", r.Method, r.URL.Path)
		}
		if got := r.Header.Get("X-Provisioning-Secret"); got != "test-secret" {
			t.Errorf("X-Provisioning-Secret = %q; want test-secret", got)
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
		Secret:   "test-secret",
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
			if _, err := ProvisionAuthKey(ProvisionAuthKeyParams{URL: ts.URL, Secret: "s", DeviceID: "d"}); err == nil {
				t.Fatal("ProvisionAuthKey() = nil error; want one")
			}
		})
	}
}

// TestProvisionAuthKey_NoSecret verifies an unstamped build with no env
// override fails with ErrNoSecret before touching the network.
func TestProvisionAuthKey_NoSecret(t *testing.T) {
	t.Setenv("QUARK_PROVISIONING_SECRET", "")
	prior := provisioningSecret
	provisioningSecret = ""
	defer func() { provisioningSecret = prior }()

	_, err := ProvisionAuthKey(ProvisionAuthKeyParams{URL: "http://127.0.0.1:0/provision"})
	if !errors.Is(err, ErrNoSecret) {
		t.Fatalf("err = %v; want ErrNoSecret", err)
	}
}

func TestSecretFromEnvOrBuild_EnvOverridesBuild(t *testing.T) {
	prior := provisioningSecret
	provisioningSecret = "stamped"
	defer func() { provisioningSecret = prior }()

	t.Setenv("QUARK_PROVISIONING_SECRET", "")
	if got := secretFromEnvOrBuild(); got != "stamped" {
		t.Errorf("with no env, secret = %q; want the stamped one", got)
	}
	t.Setenv("QUARK_PROVISIONING_SECRET", "dev")
	if got := secretFromEnvOrBuild(); got != "dev" {
		t.Errorf("with env set, secret = %q; want dev", got)
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
