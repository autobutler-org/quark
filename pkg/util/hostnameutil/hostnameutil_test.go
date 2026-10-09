package hostnameutil_test

import (
	"context"
	"errors"
	"io"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/hostnameutil"
)

// fakeSystem records every command with its stdin, and answers Avahi's
// GetHostName with advertised.
type fakeSystem struct {
	reason        hostnameutil.Reason
	advertised    string
	helperErr     error
	refreshErr    error
	calls         [][]string
	certRefreshes int
}

func (f *fakeSystem) system(t *testing.T) hostnameutil.System {
	t.Helper()
	return hostnameutil.System{
		Unavailable: func() hostnameutil.Reason { return f.reason },
		Hostname:    func() (string, error) { return "quark", nil },
		Run: func(_ context.Context, stdin io.Reader, name string, args ...string) ([]byte, error) {
			in := ""
			if stdin != nil {
				b, err := io.ReadAll(stdin)
				if err != nil {
					t.Fatal(err)
				}
				in = string(b)
			}
			f.calls = append(f.calls, append(append([]string{name}, args...), "stdin="+in))
			switch name {
			case "sudo":
				return []byte("helper output"), f.helperErr
			case "busctl":
				if f.advertised == "" {
					return []byte("Call failed: no such name"), errors.New("exit status 1")
				}
				return []byte(`{"type":"s","data":["` + f.advertised + `"]}` + "\n"), nil
			}
			t.Fatalf("unexpected command %s %v", name, args)
			return nil, nil
		},
		RefreshCertificate: func() error {
			f.certRefreshes++
			return f.refreshErr
		},
	}
}

func TestSetHostname_RejectsInvalidNames(t *testing.T) {
	invalid := []string{
		"",
		"-kitchen",
		"kitchen-",
		"Kitchen",
		"kitchen quark",
		"kitchen.local",
		"kitchen_quark",
		"quark\u00e9",
		"kitchen\n",
		"kitchen\nreboot",
		" kitchen",
		"kitchen;reboot",
		"$(reboot)",
		"`reboot`",
		"kitchen\x00",
		"../etc/passwd",
		strings.Repeat("a", 64),
		// inet_aton reads a bare number as an address: `ping 123` is 0.0.0.123.
		"123",
		"localhost",
	}
	for _, name := range invalid {
		f := &fakeSystem{}
		_, err := hostnameutil.SetHostname(context.Background(), hostnameutil.SetHostnameParams{System: f.system(t), Hostname: name})
		if !errors.Is(err, hostnameutil.ErrInvalidHostname) {
			t.Errorf("SetHostname(%q) = %v, want ErrInvalidHostname", name, err)
		}
		if len(f.calls) != 0 || f.certRefreshes != 0 {
			t.Errorf("SetHostname(%q) ran %v before rejecting the name", name, f.calls)
		}
	}
}

func TestSetHostname_AcceptsRFC1123Labels(t *testing.T) {
	for _, name := range []string{"a", "quark", "kitchen-quark", "quark2", "2quark", "a-1", strings.Repeat("a", 63)} {
		f := &fakeSystem{advertised: name}
		got, err := hostnameutil.SetHostname(context.Background(), hostnameutil.SetHostnameParams{System: f.system(t), Hostname: name})
		if err != nil {
			t.Errorf("SetHostname(%q) = %v", name, err)
			continue
		}
		if got.Hostname != name || got.AdvertisedHostname != name {
			t.Errorf("SetHostname(%q) = %+v", name, got)
		}
	}
}

// The name reaches the root helper on stdin and nowhere else: sudo runs the
// helper with no arguments, and no shell is involved.
func TestSetHostname_RunsTheHelperThenRefreshesTheCert(t *testing.T) {
	f := &fakeSystem{advertised: "kitchen-2"}
	got, err := hostnameutil.SetHostname(context.Background(), hostnameutil.SetHostnameParams{System: f.system(t), Hostname: "kitchen"})
	if err != nil {
		t.Fatalf("SetHostname: %v", err)
	}
	if len(f.calls) != 2 {
		t.Fatalf("ran %v, want the helper then one Avahi query", f.calls)
	}
	if want := []string{"sudo", "-n", hostnameutil.HelperPath, "stdin=kitchen\n"}; !slices.Equal(f.calls[0], want) {
		t.Errorf("helper call = %v, want %v", f.calls[0], want)
	}
	if f.calls[1][0] != "busctl" || !slices.Contains(f.calls[1], "--auto-start=no") || !slices.Contains(f.calls[1], "GetHostName") {
		t.Errorf("Avahi query = %v, want a busctl GetHostName that starts nothing", f.calls[1])
	}
	if f.certRefreshes != 1 {
		t.Errorf("certificate refreshed %d times, want 1", f.certRefreshes)
	}
	// Another device already answers to kitchen.local, so Avahi took the next
	// free name; the result says what this Quark really advertises.
	if got.Hostname != "kitchen" || got.AdvertisedHostname != "kitchen-2" {
		t.Errorf("result = %+v, want kitchen advertised as kitchen-2", got)
	}
}

func TestSetHostname_Unavailable(t *testing.T) {
	for _, reason := range []hostnameutil.Reason{hostnameutil.ReasonUnsupportedOS, hostnameutil.ReasonNotService, hostnameutil.ReasonHelperMissing} {
		f := &fakeSystem{reason: reason}
		_, err := hostnameutil.SetHostname(context.Background(), hostnameutil.SetHostnameParams{System: f.system(t), Hostname: "kitchen"})
		if !errors.Is(err, hostnameutil.ErrUnavailable) {
			t.Errorf("%s: SetHostname = %v, want ErrUnavailable", reason, err)
		}
		if len(f.calls) != 0 || f.certRefreshes != 0 {
			t.Errorf("%s: ran %v on a Quark that can't be renamed", reason, f.calls)
		}
	}
}

func TestSetHostname_HelperFailure(t *testing.T) {
	f := &fakeSystem{helperErr: errors.New("exit status 1")}
	_, err := hostnameutil.SetHostname(context.Background(), hostnameutil.SetHostnameParams{System: f.system(t), Hostname: "kitchen"})
	if err == nil || !strings.Contains(err.Error(), "helper output") {
		t.Errorf("SetHostname = %v, want the helper's failure with its output", err)
	}
	if errors.Is(err, hostnameutil.ErrInvalidHostname) || errors.Is(err, hostnameutil.ErrUnavailable) {
		t.Errorf("a helper failure was reported as %v", err)
	}
	if f.certRefreshes != 0 {
		t.Error("certificate refreshed although the hostname did not change")
	}
}

// The hostname has already changed when the cert is refreshed, so a failure
// there must not report the rename as failed: the next start regenerates it.
func TestSetHostname_SucceedsWhenTheCertRefreshFails(t *testing.T) {
	f := &fakeSystem{refreshErr: errors.New("disk full")}
	got, err := hostnameutil.SetHostname(context.Background(), hostnameutil.SetHostnameParams{System: f.system(t), Hostname: "kitchen"})
	if err != nil || got.Hostname != "kitchen" {
		t.Errorf("SetHostname = %+v, %v; want kitchen", got, err)
	}
	// Avahi did not answer, so nothing is known about the advertised name.
	if got.AdvertisedHostname != "" {
		t.Errorf("advertised hostname = %q, want none", got.AdvertisedHostname)
	}
}

func TestGetHostname(t *testing.T) {
	f := &fakeSystem{advertised: "quark-2"}
	got, err := hostnameutil.GetHostname(context.Background(), hostnameutil.GetHostnameParams{System: f.system(t)})
	if err != nil {
		t.Fatalf("GetHostname: %v", err)
	}
	want := hostnameutil.GetHostnameResult{Available: true, Hostname: "quark", AdvertisedHostname: "quark-2"}
	if got != want {
		t.Errorf("GetHostname = %+v, want %+v", got, want)
	}

	// A Quark that can't be renamed still says what it is called, and runs
	// nothing to find out.
	f = &fakeSystem{reason: hostnameutil.ReasonUnsupportedOS, advertised: "quark-2"}
	got, err = hostnameutil.GetHostname(context.Background(), hostnameutil.GetHostnameParams{System: f.system(t)})
	if err != nil {
		t.Fatalf("GetHostname: %v", err)
	}
	want = hostnameutil.GetHostnameResult{Reason: hostnameutil.ReasonUnsupportedOS, Hostname: "quark"}
	if got != want || len(f.calls) != 0 {
		t.Errorf("GetHostname = %+v after running %v, want %+v and no commands", got, f.calls, want)
	}
}
