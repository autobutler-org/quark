package sshutil

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"errors"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"golang.org/x/crypto/ssh"
)

type fakeCall struct {
	name  string
	args  []string
	stdin string
}

type fakeHost struct {
	reason Reason
	calls  []fakeCall
	err    error
}

func (f *fakeHost) system(t *testing.T) System {
	t.Helper()
	return System{
		Unavailable: func() Reason { return f.reason },
		Run: func(_ context.Context, stdin io.Reader, name string, args ...string) ([]byte, error) {
			in := ""
			if stdin != nil {
				b, err := io.ReadAll(stdin)
				if err != nil {
					t.Fatal(err)
				}
				in = string(b)
			}
			f.calls = append(f.calls, fakeCall{name: name, args: args, stdin: in})
			if f.err != nil {
				return []byte("helper said no"), f.err
			}
			return nil, nil
		},
		AuthorizedKeysPath: filepath.Join(t.TempDir(), ".ssh", "authorized_keys"),
	}
}

func newKeyLine(t *testing.T, comment string) (string, string) {
	t.Helper()
	pub, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	sshPub, err := ssh.NewPublicKey(pub)
	if err != nil {
		t.Fatal(err)
	}
	line := strings.TrimSpace(string(ssh.MarshalAuthorizedKey(sshPub))) + " " + comment
	return line, ssh.FingerprintSHA256(sshPub)
}

func TestKeys_AddListRemove(t *testing.T) {
	host := &fakeHost{}
	sys := host.system(t)
	line, fingerprint := newKeyLine(t, "me@laptop")

	// Options are dropped: an admin pasting a restricted key gets the key alone.
	added, err := AddKey(AddKeyParams{System: sys, Key: `command="/bin/true" ` + line + "\n"})
	if err != nil {
		t.Fatal(err)
	}
	if added.Key.Fingerprint != fingerprint || added.Key.Type != "ssh-ed25519" || added.Key.Comment != "me@laptop" {
		t.Errorf("added = %+v", added.Key)
	}
	data, err := os.ReadFile(sys.AuthorizedKeysPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != line+"\n" {
		t.Errorf("authorized_keys = %q, want %q", data, line+"\n")
	}
	for path, want := range map[string]os.FileMode{sys.AuthorizedKeysPath: 0o600, filepath.Dir(sys.AuthorizedKeysPath): 0o700} {
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm() != want {
			t.Errorf("%s mode = %o, want %o", path, info.Mode().Perm(), want)
		}
	}

	if _, err := AddKey(AddKeyParams{System: sys, Key: line}); !errors.Is(err, ErrKeyExists) {
		t.Errorf("adding the same key again = %v, want ErrKeyExists", err)
	}
	other, _ := newKeyLine(t, "")
	if _, err := AddKey(AddKeyParams{System: sys, Key: other}); err != nil {
		t.Fatal(err)
	}

	status, err := GetStatus(context.Background(), GetStatusParams{System: sys})
	if err != nil {
		t.Fatal(err)
	}
	if !status.Available || !status.Enabled || len(status.Keys) != 2 || status.Keys[0].Fingerprint != fingerprint {
		t.Errorf("status = %+v", status)
	}

	if _, err := RemoveKey(RemoveKeyParams{System: sys, Fingerprint: fingerprint}); err != nil {
		t.Fatal(err)
	}
	if _, err := RemoveKey(RemoveKeyParams{System: sys, Fingerprint: fingerprint}); !errors.Is(err, ErrKeyNotFound) {
		t.Errorf("removing it again = %v, want ErrKeyNotFound", err)
	}
	keys, err := listKeys(sys.AuthorizedKeysPath)
	if err != nil {
		t.Fatal(err)
	}
	if len(keys) != 1 || keys[0].Fingerprint == fingerprint {
		t.Errorf("keys after remove = %+v", keys)
	}
}

func TestAddKey_RejectsWhatIsNotOneKey(t *testing.T) {
	sys := (&fakeHost{}).system(t)
	one, _ := newKeyLine(t, "a")
	two, _ := newKeyLine(t, "b")
	for name, key := range map[string]string{
		"empty":     "  ",
		"garbage":   "not a key",
		"private":   "-----BEGIN OPENSSH PRIVATE KEY-----",
		"two lines": one + "\n" + two,
		"too long":  "ssh-ed25519 " + strings.Repeat("A", maxKeyLength),
	} {
		if _, err := AddKey(AddKeyParams{System: sys, Key: key}); !errors.Is(err, ErrInvalidKey) {
			t.Errorf("%s: err = %v, want ErrInvalidKey", name, err)
		}
	}
}

func TestSetEnabled_RunsTheHelperThroughSudo(t *testing.T) {
	for _, enabled := range []bool{true, false} {
		host := &fakeHost{}
		if _, err := SetEnabled(context.Background(), SetEnabledParams{System: host.system(t), Enabled: enabled}); err != nil {
			t.Fatal(err)
		}
		want := "disable"
		if enabled {
			want = "enable"
		}
		if len(host.calls) != 1 || host.calls[0].name != "sudo" || !slices.Equal(host.calls[0].args, []string{"-n", HelperPath, want}) {
			t.Errorf("enabled=%v calls = %+v", enabled, host.calls)
		}
	}
}

func TestSetPassword_GoesOnStdinOnly(t *testing.T) {
	host := &fakeHost{}
	const password = "correct horse battery"
	if _, err := SetPassword(context.Background(), SetPasswordParams{System: host.system(t), Password: password}); err != nil {
		t.Fatal(err)
	}
	if len(host.calls) != 1 {
		t.Fatalf("calls = %+v", host.calls)
	}
	call := host.calls[0]
	if !slices.Equal(call.args, []string{"-n", HelperPath, "set-password"}) || call.stdin != password+"\n" {
		t.Errorf("call = %+v", call)
	}
	for _, arg := range call.args {
		if strings.Contains(arg, password) {
			t.Error("password appeared on the command line")
		}
	}

	if _, err := ClearPassword(context.Background(), ClearPasswordParams{System: host.system(t)}); err != nil {
		t.Fatal(err)
	}
	if got := host.calls[1].args; !slices.Equal(got, []string{"-n", HelperPath, "clear-password"}) {
		t.Errorf("clear args = %v", got)
	}
}

func TestSetPassword_Validation(t *testing.T) {
	host := &fakeHost{}
	sys := host.system(t)
	for password, want := range map[string]error{
		"short":                          ErrPasswordTooShort,
		"twelve chars\nline two":         ErrInvalidPassword,
		strings.Repeat("x", 2000):        ErrInvalidPassword,
		"tab\tinside twelve characters!": ErrInvalidPassword,
	} {
		if _, err := SetPassword(context.Background(), SetPasswordParams{System: sys, Password: password}); !errors.Is(err, want) {
			t.Errorf("%q: err = %v, want %v", password, err, want)
		}
	}
	if len(host.calls) != 0 {
		t.Errorf("rejected passwords reached the helper: %+v", host.calls)
	}
}

func TestHelperFailureCarriesItsOutput(t *testing.T) {
	host := &fakeHost{err: errors.New("exit status 1")}
	_, err := SetEnabled(context.Background(), SetEnabledParams{System: host.system(t), Enabled: true})
	if err == nil || !strings.Contains(err.Error(), "helper said no") {
		t.Errorf("err = %v, want the helper's output in it", err)
	}
}

func TestUnavailable_RefusesEveryChange(t *testing.T) {
	host := &fakeHost{reason: ReasonHelperMissing}
	sys := host.system(t)
	ctx := context.Background()
	line, fingerprint := newKeyLine(t, "")

	status, err := GetStatus(ctx, GetStatusParams{System: sys})
	if err != nil || status.Available || status.Reason != ReasonHelperMissing {
		t.Errorf("status = %+v, %v", status, err)
	}
	errs := []error{}
	_, e := SetEnabled(ctx, SetEnabledParams{System: sys, Enabled: true})
	errs = append(errs, e)
	_, e = AddKey(AddKeyParams{System: sys, Key: line})
	errs = append(errs, e)
	_, e = RemoveKey(RemoveKeyParams{System: sys, Fingerprint: fingerprint})
	errs = append(errs, e)
	_, e = SetPassword(ctx, SetPasswordParams{System: sys, Password: "long enough password"})
	errs = append(errs, e)
	_, e = ClearPassword(ctx, ClearPasswordParams{System: sys})
	errs = append(errs, e)
	for i, err := range errs {
		if !errors.Is(err, ErrUnavailable) {
			t.Errorf("change %d: err = %v, want ErrUnavailable", i, err)
		}
	}
	if len(host.calls) != 0 {
		t.Errorf("an unavailable host ran commands: %+v", host.calls)
	}
}
