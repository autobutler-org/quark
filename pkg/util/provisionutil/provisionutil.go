// Package provisionutil asks the provisioning service (cmd/provisioning) for a
// Headscale pre-auth key, so enabling remote access never needs a key from the
// user (#1876).
package provisionutil

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"
)

const defaultProvisioningURL = "https://network.quark.ts.autobutler.org/provision"

// provisioningSecret is stamped into release builds by .goreleaser.yaml:
//
//	-X github.com/autobutler-org/quark/pkg/util/provisionutil.provisioningSecret=...
//
// from the QUARK_PROVISIONING_SECRET repository secret.
//
// It is effectively public: it ships in every binary, and anyone holding one
// can pull it out. It only keeps drive-by traffic off the endpoint. What
// protects the tailnet is the Headscale ACL that denies node-to-node traffic
// (autobutler-org/iac#7), pre-auth keys that are single-use and expire in an
// hour, and the provisioning service's rate limits.
var provisioningSecret string

// ErrNoSecret means this build carries no provisioning secret and none was set
// in the environment, so it cannot ask for a key.
var ErrNoSecret = errors.New(
	"no provisioning secret: this build was not stamped with one and QUARK_PROVISIONING_SECRET is not set",
)

// ProvisionAuthKeyParams configures one request for a key. Every field is
// optional; empty means the default.
type ProvisionAuthKeyParams struct {
	// URL is the provisioning endpoint. Empty means QUARK_PROVISIONING_URL,
	// or the production endpoint when that is unset.
	URL string
	// Secret is sent as X-Provisioning-Secret. Empty means
	// QUARK_PROVISIONING_SECRET, or the secret stamped in at build time.
	Secret string
	// DeviceID identifies this Quark to the service's rate limiter. Empty
	// means the sha256 of the hostname and machine-id.
	DeviceID string
}

// ProvisionAuthKeyResult carries the key the service minted.
type ProvisionAuthKeyResult struct {
	// AuthKey is a single-use Headscale pre-auth key.
	AuthKey string
}

// ProvisionAuthKey asks the provisioning service for a fresh pre-auth key.
// It fails with ErrNoSecret before any network call when there is no secret.
func ProvisionAuthKey(params ProvisionAuthKeyParams) (ProvisionAuthKeyResult, error) {
	url := params.URL
	if url == "" {
		url = provisioningURL()
	}
	secret := params.Secret
	if secret == "" {
		secret = secretFromEnvOrBuild()
	}
	if secret == "" {
		return ProvisionAuthKeyResult{}, ErrNoSecret
	}
	deviceID := params.DeviceID
	if deviceID == "" {
		deviceID = defaultDeviceID()
	}

	body, err := json.Marshal(provisionRequest{DeviceID: deviceID})
	if err != nil {
		return ProvisionAuthKeyResult{}, fmt.Errorf("marshal provision request: %w", err)
	}
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return ProvisionAuthKeyResult{}, fmt.Errorf("create provision request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Provisioning-Secret", secret)

	client := &http.Client{Timeout: requestTimeout}
	resp, err := client.Do(req)
	if err != nil {
		return ProvisionAuthKeyResult{}, fmt.Errorf("provision request: %w", err)
	}
	defer resp.Body.Close()

	// The reply is a short JSON object; anything longer is not one.
	respBody, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes+1))
	if err != nil {
		return ProvisionAuthKeyResult{}, fmt.Errorf("read provision response: %w", err)
	}
	if len(respBody) > maxResponseBytes {
		return ProvisionAuthKeyResult{}, fmt.Errorf("provision response is over %d bytes", maxResponseBytes)
	}
	if resp.StatusCode != http.StatusOK {
		return ProvisionAuthKeyResult{}, fmt.Errorf("provisioning service returned %d: %s", resp.StatusCode, respBody)
	}
	var pResp provisionResponse
	if err := json.Unmarshal(respBody, &pResp); err != nil {
		return ProvisionAuthKeyResult{}, fmt.Errorf("parse provision response: %w", err)
	}
	if pResp.AuthKey == "" {
		return ProvisionAuthKeyResult{}, errors.New("provisioning service returned an empty auth key")
	}
	return ProvisionAuthKeyResult(pResp), nil
}

// requestTimeout bounds the whole exchange, so a hung provisioning service
// fails an enable rather than holding it open.
const requestTimeout = 15 * time.Second

// maxResponseBytes caps what is read from the service.
const maxResponseBytes = 4096
