// cspell:words thumbversionutil

package thumbversionutil_test

import (
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/thumbversionutil"
)

func TestVersion(t *testing.T) {
	at := time.Unix(1700000000, 999_000_000)
	if got := thumbversionutil.Version(at, 0); got != "1700000000.0" {
		t.Errorf("Version = %q, want 1700000000.0", got)
	}
	if got := thumbversionutil.Version(at, 3); got != "1700000000.3" {
		t.Errorf("Version = %q, want 1700000000.3", got)
	}
	if got := thumbversionutil.AvatarVersion(at); got != "1700000000999" {
		t.Errorf("AvatarVersion = %q, want 1700000000999", got)
	}
}

func TestCacheControl(t *testing.T) {
	cases := []struct{ requested, current, want string }{
		{"", "1.0", thumbversionutil.Revalidate},
		{"1.0", "1.0", thumbversionutil.Immutable},
		{"1.0", "1.1", thumbversionutil.Revalidate},
		// No current version: nothing a client names can match it.
		{"", "", thumbversionutil.Revalidate},
		{"1.0", "", thumbversionutil.Revalidate},
	}
	for _, tc := range cases {
		if got := thumbversionutil.CacheControl(tc.requested, tc.current); got != tc.want {
			t.Errorf("CacheControl(%q, %q) = %q, want %q", tc.requested, tc.current, got, tc.want)
		}
	}
}
