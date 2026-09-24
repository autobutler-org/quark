package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

// usersJSON is `headscale users list -o json` from v0.28: encoding/json over
// the generated structs, so IDs are numbers and timestamps are objects.
const usersJSON = `[
	{"id": 3, "name": "someone-else"},
	{"id": 7, "name": "household-existing", "created_at": {"seconds": 1767225600}}
]`

// keyJSON is `headscale preauthkeys create -o json` from v0.28.
const keyJSON = `{"user": {"id": 7, "name": "household-existing"}, "id": 12, "key": "hskey-auth-abc", "expiration": {"seconds": 1767229200}}`

// fakeHeadscale is a stateful stand-in for the headscale CLI: it lists and
// creates users, and mints a key for any user it knows. Any other command line
// fails the test.
type fakeHeadscale struct {
	mu sync.Mutex
	// users maps a name to its ID.
	users map[string]uint64
	// created lists the users `users create` made, in order.
	created []string
	// keyedFor lists the user IDs keys were minted for, in order.
	keyedFor []uint64
}

func fakeCLI(t *testing.T, users string) *fakeHeadscale {
	t.Helper()
	var parsed []headscaleUserJSON
	if err := json.Unmarshal([]byte(users), &parsed); err != nil {
		t.Fatalf("parse users fixture: %v", err)
	}
	fake := &fakeHeadscale{users: map[string]uint64{}}
	for _, u := range parsed {
		fake.users[u.Name] = u.ID
	}
	prior := runHeadscale
	t.Cleanup(func() { runHeadscale = prior })
	runHeadscale = func(_ context.Context, args ...string) ([]byte, error) {
		fake.mu.Lock()
		defer fake.mu.Unlock()
		cmd := strings.Join(args, " ")
		switch {
		case cmd == "users list -o json":
			list := []headscaleUserJSON{}
			for name, id := range fake.users {
				list = append(list, headscaleUserJSON{ID: id, Name: name})
			}
			return json.Marshal(list)
		case len(args) == 5 && args[0] == "users" && args[1] == "create" && args[3] == "-o":
			if _, ok := fake.users[args[2]]; ok {
				t.Errorf("users create %q for a user that exists; want list-then-create", args[2])
				return nil, errors.New("user already exists")
			}
			id := uint64(100 + len(fake.created))
			fake.users[args[2]] = id
			fake.created = append(fake.created, args[2])
			return json.Marshal(headscaleUserJSON{ID: id, Name: args[2]})
		case len(args) == 8 && args[0] == "preauthkeys" && args[1] == "create" &&
			strings.Join(args[4:], " ") == "--expiration 1h -o json":
			id, err := strconv.ParseUint(args[3], 10, 64)
			if err != nil {
				t.Errorf("preauthkeys create --user %q; want a numeric ID", args[3])
				return nil, err
			}
			fake.keyedFor = append(fake.keyedFor, id)
			return []byte(keyJSON), nil
		default:
			t.Errorf("unexpected headscale command: %q", args)
			return nil, errors.New("unexpected command")
		}
	}
	return fake
}

// setup configures the service and clears the rate limiter.
func setup(t *testing.T, users string) *fakeHeadscale {
	t.Helper()
	fake := fakeCLI(t, users)
	householdKey = []byte("test-household-key")
	keyExpiry = time.Hour
	rateMu.Lock()
	rateStore = make(map[string]*rateLimitEntry)
	rateMu.Unlock()
	return fake
}

func provisionBody(t *testing.T, body provisionRequest, remoteAddr, realIP string) *httptest.ResponseRecorder {
	t.Helper()
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodPost, "/provision", strings.NewReader(string(raw)))
	req.RemoteAddr = remoteAddr
	if realIP != "" {
		req.Header.Set("X-Real-IP", realIP)
	}
	w := httptest.NewRecorder()
	handleProvision(w, req)
	return w
}

// provision is a cold enrollment: a device ID and no household credential.
func provision(t *testing.T, deviceID, remoteAddr, realIP string) *httptest.ResponseRecorder {
	t.Helper()
	return provisionBody(t, provisionRequest{DeviceID: deviceID}, remoteAddr, realIP)
}

// pair is a pair-mode request presenting household and token.
func pair(t *testing.T, deviceID, household, token, remoteAddr string) *httptest.ResponseRecorder {
	t.Helper()
	return provisionBody(t, provisionRequest{DeviceID: deviceID, Household: household, HouseholdToken: token}, remoteAddr, "")
}

func decode(t *testing.T, w *httptest.ResponseRecorder) provisionResponse {
	t.Helper()
	var resp provisionResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("response %s: %v", w.Body.String(), err)
	}
	return resp
}

// TestProvision_FirstEnrollmentCreatesHousehold verifies a request with no
// household credential creates a randomly named Headscale user and returns
// its key, name and token. It also covers #1879: the request carries no
// secret header and still gets a key.
func TestProvision_FirstEnrollmentCreatesHousehold(t *testing.T) {
	fake := setup(t, usersJSON)

	w := provision(t, "device-1", "203.0.113.5:4000", "")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d; want 200: %s", w.Code, w.Body.String())
	}
	resp := decode(t, w)
	if resp.AuthKey != "hskey-auth-abc" {
		t.Errorf("auth_key = %q; want hskey-auth-abc", resp.AuthKey)
	}
	if len(fake.created) != 1 || fake.created[0] != resp.Household || !strings.HasPrefix(resp.Household, "household-") {
		t.Fatalf("created users %q, household %q; want one new household user named in the response", fake.created, resp.Household)
	}
	if resp.HouseholdToken != householdToken(resp.Household) || len(resp.HouseholdToken) != 64 {
		t.Errorf("household_token = %q; want HMAC-SHA256 of the household", resp.HouseholdToken)
	}
	if got := fake.keyedFor; len(got) != 1 || got[0] != fake.users[resp.Household] {
		t.Errorf("keys minted for %v; want one for the new household's user", got)
	}
}

// TestProvision_TwoEnrollmentsTwoHouseholds verifies two Quarks enrolled in a
// row land in two different Headscale users.
func TestProvision_TwoEnrollmentsTwoHouseholds(t *testing.T) {
	fake := setup(t, usersJSON)

	a := decode(t, provision(t, "device-a", "203.0.113.5:4000", ""))
	b := decode(t, provision(t, "device-b", "203.0.113.6:4000", ""))
	if a.Household == b.Household || len(fake.created) != 2 {
		t.Errorf("households %q and %q, created %q; want two distinct new users", a.Household, b.Household, fake.created)
	}
}

// TestProvision_PairModeMintsForHousehold verifies a valid household and
// token get a key for that household's existing user: list-then-create finds
// it, so nothing is created.
func TestProvision_PairModeMintsForHousehold(t *testing.T) {
	fake := setup(t, usersJSON)

	w := pair(t, "phone-1", "household-existing", householdToken("household-existing"), "203.0.113.5:4000")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d; want 200: %s", w.Code, w.Body.String())
	}
	resp := decode(t, w)
	if resp.Household != "household-existing" || resp.AuthKey != "hskey-auth-abc" {
		t.Errorf("response = %+v; want a key in household-existing", resp)
	}
	if len(fake.created) != 0 {
		t.Errorf("created %q; want no user created for a household that exists", fake.created)
	}
	if got := fake.keyedFor; len(got) != 1 || got[0] != 7 {
		t.Errorf("keys minted for %v; want [7], the household's user", got)
	}
}

// TestProvision_PairModeRejectsBadCredential verifies a wrong token, a
// household with no token, and a token with no household are all 401, and
// that nothing reaches headscale.
func TestProvision_PairModeRejectsBadCredential(t *testing.T) {
	fake := setup(t, usersJSON)
	valid := householdToken("household-existing")

	cases := map[string]provisionRequest{
		"wrong token":             {DeviceID: "phone-1", Household: "household-existing", HouseholdToken: strings.Repeat("0", 64)},
		"another household token": {DeviceID: "phone-1", Household: "household-existing", HouseholdToken: householdToken("someone-else")},
		"household without token": {DeviceID: "phone-1", Household: "household-existing"},
		"token without household": {DeviceID: "phone-1", HouseholdToken: valid},
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			if w := provisionBody(t, body, "203.0.113.5:4000", ""); w.Code != http.StatusUnauthorized {
				t.Errorf("status = %d; want 401: %s", w.Code, w.Body.String())
			}
		})
	}
	if len(fake.keyedFor) != 0 || len(fake.created) != 0 {
		t.Errorf("keys minted %v, users created %q; want none", fake.keyedFor, fake.created)
	}
}

// TestProvision_PairModeUsesHouseholdBucket verifies pair requests from one IP
// for one household are limited by the household bucket, not the per-IP one:
// a family of six pairs within the hour, the household's looser limit holds,
// pairing does not use up the IP's cold-enrollment allowance, and another
// household behind the same address is unaffected.
func TestProvision_PairModeUsesHouseholdBucket(t *testing.T) {
	setup(t, `[{"id": 7, "name": "household-existing"}, {"id": 8, "name": "household-other"}]`)
	token := householdToken("household-existing")

	// A family of six behind one NAT address, over the per-IP limit of five.
	for i := range 6 {
		if w := pair(t, fmt.Sprintf("phone-%d", i), "household-existing", token, "203.0.113.5:4000"); w.Code != http.StatusOK {
			t.Fatalf("family pair %d: status = %d; want 200", i+1, w.Code)
		}
	}
	for i := 6; i < maxHouseholdRequestsPerHour; i++ {
		if w := pair(t, fmt.Sprintf("phone-%d", i), "household-existing", token, "203.0.113.5:4000"); w.Code != http.StatusOK {
			t.Fatalf("pair %d: status = %d; want 200", i+1, w.Code)
		}
	}
	if w := pair(t, "phone-over", "household-existing", token, "203.0.113.5:4000"); w.Code != http.StatusTooManyRequests {
		t.Errorf("pair over the household limit: status = %d; want 429", w.Code)
	}
	if w := pair(t, "phone-x", "household-other", householdToken("household-other"), "203.0.113.5:4000"); w.Code != http.StatusOK {
		t.Errorf("another household from the same IP: status = %d; want 200", w.Code)
	}
	if w := provision(t, "quark-new", "203.0.113.5:4000", ""); w.Code != http.StatusOK {
		t.Errorf("cold enrollment from the same IP: status = %d; want 200, pairing does not use the IP bucket", w.Code)
	}
}

// TestEnsureUserID_CreateFailure verifies a household user that cannot be
// created fails the request rather than minting a key for someone else.
func TestEnsureUserID_CreateFailure(t *testing.T) {
	setup(t, usersJSON)
	runHeadscale = func(_ context.Context, args ...string) ([]byte, error) {
		if args[1] == "list" {
			return []byte(usersJSON), nil
		}
		if args[1] == "create" && args[0] == "users" {
			return []byte(`{"id": 0}`), nil
		}
		t.Errorf("unexpected headscale command: %q", args)
		return nil, errors.New("unexpected command")
	}
	if _, err := ensureUserID(context.Background(), "household-new"); err == nil {
		t.Error("ensureUserID() = nil error for a create with no ID; want one")
	}
	if w := provision(t, "device-1", "203.0.113.5:4000", ""); w.Code != http.StatusInternalServerError {
		t.Errorf("status = %d; want 500", w.Code)
	}
}

func TestCreatePreAuthKey_CLIFailure(t *testing.T) {
	setup(t, usersJSON)
	runHeadscale = func(context.Context, ...string) ([]byte, error) {
		return nil, errors.New("headscale users list failed (stderr is in the log): exit status 1")
	}
	if _, err := createPreAuthKey(context.Background(), "household-existing"); err == nil || !strings.Contains(err.Error(), "exit status 1") {
		t.Errorf("createPreAuthKey() = %v; want the CLI failure", err)
	}
	if w := provision(t, "device-1", "203.0.113.5:4000", ""); w.Code != http.StatusInternalServerError {
		t.Errorf("status = %d; want 500", w.Code)
	}
}

// TestCreatePreAuthKey_UnparsableKeepsKeyOutOfError verifies a create whose
// output does not parse fails without echoing that output, which may hold a
// key, into the error the handler logs.
func TestCreatePreAuthKey_UnparsableKeepsKeyOutOfError(t *testing.T) {
	setup(t, usersJSON)
	runHeadscale = func(_ context.Context, args ...string) ([]byte, error) {
		if args[0] == "users" {
			return []byte(usersJSON), nil
		}
		return []byte(`hskey-auth-leaked not json`), nil
	}
	_, err := createPreAuthKey(context.Background(), "household-existing")
	if err == nil || strings.Contains(err.Error(), "hskey-auth-leaked") {
		t.Errorf("createPreAuthKey() = %v; want an error without the output", err)
	}
}

// TestRunHeadscale_RealProcess runs the real exec path against stand-in
// binaries: stdout is returned, and a non-zero exit or a missing binary is an
// error rather than a panic.
func TestRunHeadscale_RealProcess(t *testing.T) {
	prior := headscaleBin
	t.Cleanup(func() { headscaleBin = prior })

	headscaleBin = "echo"
	out, err := runHeadscale(context.Background(), "users", "list")
	if err != nil || strings.TrimSpace(string(out)) != "users list" {
		t.Errorf("runHeadscale(echo) = %q, %v; want the args echoed", out, err)
	}

	headscaleBin = "false"
	if _, err := runHeadscale(context.Background(), "users", "list"); err == nil || !strings.Contains(err.Error(), "headscale users list failed") {
		t.Errorf("runHeadscale(false) = %v; want a failure naming the command", err)
	}

	headscaleBin = "/nonexistent/headscale"
	if _, err := runHeadscale(context.Background(), "users", "list"); err == nil {
		t.Error("runHeadscale(missing binary) = nil error; want one")
	}
}

func TestCappedBuffer(t *testing.T) {
	b := &cappedBuffer{max: 3}
	for _, chunk := range []string{"ab", "xyz", "gh"} {
		if n, err := b.Write([]byte(chunk)); n != len(chunk) || err != nil {
			t.Fatalf("Write(%q) = %d, %v; want every byte accepted", chunk, n, err)
		}
	}
	if b.buf.String() != "abx" || !b.overflow {
		t.Errorf("buffer = %q, overflow %v; want abx and overflow", b.buf.String(), b.overflow)
	}
}

// TestProvision_RateLimitsPerDevice verifies the device bucket still caps cold
// enrollment from one device.
func TestProvision_RateLimitsPerDevice(t *testing.T) {
	setup(t, usersJSON)

	for i := range maxRequestsPerHour {
		if w := provision(t, "device-1", "203.0.113.5:4000", ""); w.Code != http.StatusOK {
			t.Fatalf("request %d: status = %d; want 200", i+1, w.Code)
		}
	}
	if w := provision(t, "device-1", "203.0.113.5:4000", ""); w.Code != http.StatusTooManyRequests {
		t.Errorf("request over the limit: status = %d; want 429", w.Code)
	}
}

// TestProvision_RateLimitsPerClientBehindProxy verifies that behind nginx on
// loopback each quark gets its own IP bucket from X-Real-IP, and that the
// header is ignored from a non-loopback peer, which could otherwise forge it.
func TestProvision_RateLimitsPerClientBehindProxy(t *testing.T) {
	setup(t, usersJSON)

	for i := range maxRequestsPerHour {
		if w := provision(t, fmt.Sprintf("device-a%d", i), "127.0.0.1:5000", "198.51.100.1"); w.Code != http.StatusOK {
			t.Fatalf("request %d: status = %d; want 200", i+1, w.Code)
		}
	}
	if w := provision(t, "device-b", "127.0.0.1:5000", "198.51.100.2"); w.Code != http.StatusOK {
		t.Errorf("a second client behind the proxy was limited: status = %d; want 200", w.Code)
	}
	if w := provision(t, "device-c", "127.0.0.1:5000", "198.51.100.1"); w.Code != http.StatusTooManyRequests {
		t.Errorf("the first client over its limit: status = %d; want 429", w.Code)
	}
}

func TestClientIP(t *testing.T) {
	cases := []struct {
		name, remoteAddr, realIP, want string
	}{
		{"direct peer", "203.0.113.5:4000", "", "203.0.113.5"},
		{"direct peer forging the header", "203.0.113.5:4000", "198.51.100.1", "203.0.113.5"},
		{"loopback proxy", "127.0.0.1:4000", "198.51.100.1", "198.51.100.1"},
		{"ipv6 loopback proxy", "[::1]:4000", "198.51.100.1", "198.51.100.1"},
		{"loopback without the header", "127.0.0.1:4000", "", "127.0.0.1"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/provision", nil)
			req.RemoteAddr = tc.remoteAddr
			if tc.realIP != "" {
				req.Header.Set("X-Real-IP", tc.realIP)
			}
			if got := clientIP(req); got != tc.want {
				t.Errorf("clientIP() = %q; want %q", got, tc.want)
			}
		})
	}
}

func TestParseKeyExpiry(t *testing.T) {
	cases := []struct {
		in      string
		want    time.Duration
		wantErr bool
	}{
		{"", time.Hour, false},
		{"1", time.Hour, false},
		{"24", 24 * time.Hour, false},
		{"0", 0, true},
		{"-3", 0, true},
		{"1h", 0, true},
		{"soon", 0, true},
	}
	for _, tc := range cases {
		got, err := parseKeyExpiry(tc.in)
		if (err != nil) != tc.wantErr || got != tc.want {
			t.Errorf("parseKeyExpiry(%q) = %v, %v; want %v, error %v", tc.in, got, err, tc.want, tc.wantErr)
		}
	}
}
