package authkey_test

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/cmd/quark/authkey"
)

// run runs quark auth-key with args and stdin, and returns what it printed.
func run(stdin string, args ...string) (stdout, stderr string, err error) {
	cmd := authkey.Cmd()
	var out, errOut bytes.Buffer
	cmd.SetOut(&out)
	cmd.SetErr(&errOut)
	cmd.SetIn(strings.NewReader(stdin))
	cmd.SetArgs(args)
	err = cmd.Execute()
	return out.String(), errOut.String(), err
}

// quarkAnswering is a server whose salt endpoint answers status and body.
func quarkAnswering(t *testing.T, status int, body string) *httptest.Server {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v0/auth/salt" || r.URL.Query().Get("username") != "ada" {
			t.Errorf("asked for %s, want the salt of ada", r.URL)
		}
		w.WriteHeader(status)
		fmt.Fprint(w, body)
	}))
	t.Cleanup(server.Close)
	return server
}

// appSalt is the salt of the app's pinned vectors: the bytes 0 through 15.
var appSalt = base64.StdEncoding.EncodeToString([]byte{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15})

// TestAuthKey_PrintsTheAppsKey checks the printed key against the vectors
// test/services/chat_crypto_test.dart pins the app to (#2713): stdout is the
// key and a newline, nothing else, and stdin is taken as one line.
func TestAuthKey_PrintsTheAppsKey(t *testing.T) {
	server := quarkAnswering(t, http.StatusOK, `{"salt":"`+appSalt+`","legacy":false,"legacyRecovery":false}`)
	for _, tc := range []struct {
		name, stdin, want string
		extra             []string
	}{
		{"the auth key", "correct horse battery staple\n", "zNR6rA8kTcAq8wwj0fjQh9lSZ0A3+VNjah0pZEMf7XU=", nil},
		{"with no newline, and a slash after the host", "correct horse battery staple", "zNR6rA8kTcAq8wwj0fjQh9lSZ0A3+VNjah0pZEMf7XU=", []string{"--host", server.URL + "/"}},
		{"the recovery key", "abandon-ability-able-about-above-absent\r\n", "mvSfNFyawdUYP8Sp/ldQ6Zg+ka7XSRpmfJyOYFcprBQ=", []string{"--recovery"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			stdout, stderr, err := run(tc.stdin, append([]string{"--host", server.URL, "-u", "ada"}, tc.extra...)...)
			if err != nil {
				t.Fatal(err)
			}
			if stdout != tc.want+"\n" || stderr != "" {
				t.Errorf("stdout = %q, stderr = %q, want only the key %q on stdout", stdout, stderr, tc.want)
			}
		})
	}
}

// TestAuthKey_NoArgumentsPrintsUsage is the self-guiding rule: a bare
// quark auth-key shows how to call it rather than failing.
func TestAuthKey_NoArgumentsPrintsUsage(t *testing.T) {
	stdout, _, err := run("")
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"Usage:", "--host", "--username", "--recovery", "stdin"} {
		if !strings.Contains(stdout, want) {
			t.Errorf("usage does not mention %q:\n%s", want, stdout)
		}
	}
}

// TestAuthKey_ErrorsSayWhatToDo drives each failure and checks its text names
// the fix, and that nothing lands on stdout for $(...) to capture.
func TestAuthKey_ErrorsSayWhatToDo(t *testing.T) {
	good := `{"salt":"` + appSalt + `"}`
	closed := httptest.NewServer(http.NotFoundHandler())
	closed.Close()
	selfSigned := httptest.NewTLSServer(http.NotFoundHandler())
	t.Cleanup(selfSigned.Close)

	for _, tc := range []struct {
		name, stdin string
		args        []string
		want        []string
	}{
		{"an unreachable host", "pw\n", []string{"--host", closed.URL, "-u", "ada"}, []string{"could not reach " + closed.URL + "/api/v0/auth/salt", "curl " + closed.URL + "/api/v0/auth/status"}},
		{"a self-signed certificate", "pw\n", []string{"--host", selfSigned.URL, "-u", "ada"}, []string{selfSigned.URL, "pass -k"}},
		{"a Quark with no salt endpoint", "pw\n", []string{"--host", quarkAnswering(t, http.StatusNotFound, "404 page not found").URL, "-u", "ada"}, []string{"404", "Update the Quark"}},
		{"a rate-limited request", "pw\n", []string{"--host", quarkAnswering(t, http.StatusTooManyRequests, "{}").URL, "-u", "ada"}, []string{"429", "Wait a minute"}},
		{"a host that is not a Quark", "pw\n", []string{"--host", quarkAnswering(t, http.StatusOK, "<html>").URL, "-u", "ada"}, []string{"did not answer with a salt", "--host"}},
		{"a host with no scheme", "pw\n", []string{"--host", "quark.local", "-u", "ada"}, []string{`"quark.local"`, "https://quark.local"}},
		{"no host", "pw\n", []string{"-u", "ada"}, []string{"--host", "https://quark.local"}},
		{"no username", "pw\n", []string{"--host", "http://localhost:1"}, []string{"-u"}},
		{"no password", "\n", []string{"--host", quarkAnswering(t, http.StatusOK, good).URL, "-u", "ada"}, []string{"no password given", "stdin"}},
		{"no phrase", "", []string{"--host", quarkAnswering(t, http.StatusOK, good).URL, "-u", "ada", "--recovery"}, []string{"no recovery phrase given"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			stdout, _, err := run(tc.stdin, tc.args...)
			if err == nil {
				t.Fatalf("no error; stdout = %q", stdout)
			}
			if stdout != "" {
				t.Errorf("stdout = %q, want nothing", stdout)
			}
			for _, want := range tc.want {
				if !strings.Contains(err.Error(), want) {
					t.Errorf("error does not mention %q:\n%v", want, err)
				}
			}
		})
	}
}

// TestAuthKey_InsecureSkipsTheCertificateCheck is -k against a self-signed
// Quark, which is what a device serves.
func TestAuthKey_InsecureSkipsTheCertificateCheck(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		fmt.Fprint(w, `{"salt":"`+appSalt+`"}`)
	}))
	t.Cleanup(server.Close)
	stdout, _, err := run("correct horse battery staple\n", "--host", server.URL, "-u", "ada", "-k")
	if err != nil || stdout != "zNR6rA8kTcAq8wwj0fjQh9lSZ0A3+VNjah0pZEMf7XU=\n" {
		t.Errorf("stdout = %q, err = %v, want the key", stdout, err)
	}
}

// TestAuthKey_NotesALegacyAccount warns on stderr, and still prints the key,
// when the Quark says the key will not work alone.
func TestAuthKey_NotesALegacyAccount(t *testing.T) {
	server := quarkAnswering(t, http.StatusOK, `{"salt":"`+appSalt+`","legacy":true,"legacyRecovery":true}`)
	for _, tc := range []struct {
		want  string
		extra []string
	}{
		{"has not moved to auth keys", nil},
		{"no recovery key yet", []string{"--recovery"}},
	} {
		stdout, stderr, err := run("a-secret\n", append([]string{"--host", server.URL, "-u", "ada"}, tc.extra...)...)
		if err != nil || !strings.HasPrefix(stderr, "note: ") || !strings.Contains(stderr, tc.want) || stdout == "" {
			t.Errorf("stdout = %q, stderr = %q, err = %v, want a key and a note with %q", stdout, stderr, err, tc.want)
		}
	}
}
