package feedutil

import (
	"context"
	"errors"
	"net"
	"strings"
	"testing"
)

func TestCheckAddress(t *testing.T) {
	token := "opaque-token"
	public := net.ParseIP("203.0.113.5")
	lookup := func(ctx context.Context, host string) ([]net.IP, error) {
		if host == "feed.example" {
			return []net.IP{public}, nil
		}
		if host == "mixed.example" {
			return []net.IP{public, net.ParseIP("10.0.0.1")}, nil
		}
		return nil, errors.New("lookup " + host + " failed")
	}
	allowed := "https://feed.example/rss?token=" + token
	for _, tc := range []struct {
		name string
		raw  string
		want error
	}{
		{name: "public name", raw: allowed},
		{name: "public ip", raw: "http://203.0.113.5/feed?token=" + token},
		{name: "empty", raw: "  ", want: ErrInvalidURL},
		{name: "ftp", raw: "ftp://203.0.113.5/feed?token=" + token, want: ErrInvalidURL},
		{name: "file", raw: "file:///etc/passwd", want: ErrInvalidURL},
		{name: "no host", raw: "http:///feed", want: ErrInvalidURL},
		{name: "backslash", raw: `http://feed.example\feed`, want: ErrInvalidURL},
		{name: "bad port", raw: "http://203.0.113.5:99999/feed", want: ErrInvalidURL},
		{name: "loopback", raw: "http://127.0.0.1/feed?token=" + token, want: ErrForbiddenAddress},
		{name: "loopback v6", raw: "http://[::1]/feed?token=" + token, want: ErrForbiddenAddress},
		{name: "mapped loopback", raw: "http://[::ffff:127.0.0.1]/feed?token=" + token, want: ErrForbiddenAddress},
		{name: "private", raw: "http://192.168.1.20/feed?token=" + token, want: ErrForbiddenAddress},
		{name: "ten network", raw: "http://10.1.2.3/feed?token=" + token, want: ErrForbiddenAddress},
		{name: "mapped private", raw: "http://[::ffff:10.1.2.3]/feed?token=" + token, want: ErrForbiddenAddress},
		{name: "link local", raw: "http://169.254.169.254/latest?token=" + token, want: ErrForbiddenAddress},
		{name: "link local v6", raw: "http://[fe80::1]/feed?token=" + token, want: ErrForbiddenAddress},
		{name: "unique local", raw: "http://[fc00::1]/feed?token=" + token, want: ErrForbiddenAddress},
		{name: "unspecified", raw: "http://0.0.0.0/feed?token=" + token, want: ErrForbiddenAddress},
		{name: "this host", raw: "http://0.1.2.3/feed?token=" + token, want: ErrForbiddenAddress},
		{name: "carrier nat", raw: "http://100.64.0.1/feed?token=" + token, want: ErrForbiddenAddress},
		{name: "userinfo hides loopback", raw: "http://feed.example:80@127.0.0.1/feed?token=" + token, want: ErrForbiddenAddress},
		{name: "unresolved", raw: "https://missing.example/feed?token=" + token, want: ErrUnresolved},
		{name: "mixed answers", raw: "https://mixed.example/feed?token=" + token, want: ErrForbiddenAddress},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, err := checkAddress(context.Background(), tc.raw, lookup)
			if !errors.Is(err, tc.want) {
				t.Fatalf("error = %v, want %v", err, tc.want)
			}
			if err != nil && (strings.Contains(err.Error(), token) || strings.Contains(err.Error(), "://")) {
				t.Fatalf("error repeats the address: %v", err)
			}
			if tc.want == nil && strings.Contains(got.String(), "#") {
				t.Fatalf("stored a fragment: %s", got)
			}
		})
	}

	got, err := checkAddress(context.Background(), "HTTP://203.0.113.5:80/a/Feed?token=Abc%2Fdef#frag", nil)
	if err != nil {
		t.Fatal(err)
	}
	if got.String() != "http://203.0.113.5/a/Feed?token=Abc%2Fdef" {
		t.Fatalf("canonical = %s", got)
	}
	if got.Query().Get("token") != "Abc/def" {
		t.Fatalf("token = %q", got.Query().Get("token"))
	}

	called := false
	if _, err := checkAddress(context.Background(), "http://203.0.113.5/feed", func(context.Context, string) ([]net.IP, error) {
		called = true
		return nil, errors.New("should not be called")
	}); err != nil || called {
		t.Fatalf("literal address err=%v lookup called=%v", err, called)
	}
}

func TestScrubStoreHidesTheURL(t *testing.T) {
	raw := "https://feed.example/x?token=opaque-token"
	unique := sqlStateErr{msg: "duplicate key value (url)=(" + raw + ")", state: "23505"}
	if err := scrubStore(unique, raw); !errors.Is(err, ErrAlreadySubscribed) || strings.Contains(err.Error(), "opaque-token") {
		t.Fatalf("unique error = %v", err)
	}
	leaked := errors.New("driver: " + raw)
	if err := scrubStore(leaked, raw); !errors.Is(err, ErrStoreFailed) || strings.Contains(err.Error(), "opaque-token") {
		t.Fatalf("leaking error = %v", err)
	}
}

type sqlStateErr struct {
	msg   string
	state string
}

func (e sqlStateErr) Error() string    { return e.msg }
func (e sqlStateErr) SQLState() string { return e.state }
