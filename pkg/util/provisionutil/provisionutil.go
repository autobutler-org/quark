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

	"github.com/autobutler-org/quark/pkg/util/settingsutil"
)

const defaultProvisioningURL = "https://quark.ts.autobutler.org/provision"

// ProvisionAuthKeyParams configures one request for a key. Every field is
// optional; empty means the default.
type ProvisionAuthKeyParams struct {
	// URL is the provisioning endpoint. Empty means QUARK_PROVISIONING_URL,
	// or the production endpoint when that is unset.
	URL string
	// DeviceID identifies the device the key is for to the service's rate
	// limiter. Empty means this Quark's DeviceID.
	DeviceID string
	// Household and HouseholdToken are the credential a first enrollment
	// returned (#2358). Set, they ask for a key in that household (pair
	// mode); empty, the service creates a new household.
	Household      string
	HouseholdToken string
}

// ProvisionAuthKeyResult carries the key the service minted and the
// household it belongs to.
type ProvisionAuthKeyResult struct {
	// AuthKey is a single-use Headscale pre-auth key.
	AuthKey string
	// Household is the Headscale user the key belongs to.
	Household string
	// HouseholdToken authenticates later pair requests for Household.
	HouseholdToken string
}

// EnrollResult carries the key for this Quark's own tsnet node.
type EnrollResult struct {
	// AuthKey is a single-use Headscale pre-auth key.
	AuthKey string
}

// DeviceID is this Quark's stable device ID: the sha256 of the hostname and
// machine-id, hex-encoded. Hosts without a machine-id (macOS, some containers)
// hash the hostname alone.
func DeviceID() string {
	return defaultDeviceID()
}

// Enroll asks for a key for this Quark's own node. It presents the household
// credential stored in settings when there is one, so a Quark re-enabled
// after Disable rejoins its own household; otherwise the service creates a
// household, and its credential is stored for next time (#2358).
func Enroll() (EnrollResult, error) {
	household, token := settingsutil.GetHousehold()
	result, err := ProvisionAuthKey(ProvisionAuthKeyParams{Household: household, HouseholdToken: token})
	if err != nil {
		return EnrollResult{}, err
	}
	if result.Household != household || result.HouseholdToken != token {
		if err := settingsutil.SetHousehold(result.Household, result.HouseholdToken); err != nil {
			return EnrollResult{}, fmt.Errorf("store household credential: %w", err)
		}
	}
	return EnrollResult{AuthKey: result.AuthKey}, nil
}

// ProvisionAuthKey asks the provisioning service for a fresh pre-auth key.
// The service takes no secret (#1879), so any build can ask.
func ProvisionAuthKey(params ProvisionAuthKeyParams) (ProvisionAuthKeyResult, error) {
	url := params.URL
	if url == "" {
		url = provisioningURL()
	}
	deviceID := params.DeviceID
	if deviceID == "" {
		deviceID = defaultDeviceID()
	}

	body, err := json.Marshal(provisionRequest{
		DeviceID:       deviceID,
		Household:      params.Household,
		HouseholdToken: params.HouseholdToken,
	})
	if err != nil {
		return ProvisionAuthKeyResult{}, fmt.Errorf("marshal provision request: %w", err)
	}
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return ProvisionAuthKeyResult{}, fmt.Errorf("create provision request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

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
