package settingsutil_test

import (
	"errors"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/settingsutil"
)

// TestValidateThemeColor checks the three shapes a theme color may take and that
// everything else is ErrInvalidThemeColor.
func TestValidateThemeColor(t *testing.T) {
	for _, tc := range []struct {
		themeColor string
		valid      bool
	}{
		{"", true},
		{"teal", true},
		{"a", true},
		{"deep-blue-2", true},
		{"a" + strings.Repeat("b", 31), true},
		{"#0ea5e9", true},
		{"#000000", true},
		{"a" + strings.Repeat("b", 32), false},
		{"Teal", false},
		{"2teal", false},
		{"-teal", false},
		{"teal blue", false},
		{"teal_blue", false},
		{"teal\n", false},
		{" teal", false},
		{"#0EA5E9", false},
		{"#0ea5e", false},
		{"#0ea5e9f", false},
		{"#0ea5e9ff", false},
		{"#ggggggg", false},
		{"#gggggg", false},
		{"0ea5e9#", false},
		{"#", false},
		{"rgb(1,2,3)", false},
		{"../../etc/passwd", false},
		{"<script>", false},
	} {
		err := settingsutil.ValidateThemeColor(tc.themeColor)
		if tc.valid && err != nil {
			t.Errorf("ValidateThemeColor(%q) = %v, want it accepted", tc.themeColor, err)
		}
		if !tc.valid && !errors.Is(err, settingsutil.ErrInvalidThemeColor) {
			t.Errorf("ValidateThemeColor(%q) = %v, want ErrInvalidThemeColor", tc.themeColor, err)
		}
	}
}

// TestThemeColor_RoundTrip checks the theme color is empty until an admin chooses,
// survives a reload beside the other settings, refuses a malformed value
// without storing it, and clears with the empty string.
func TestThemeColor_RoundTrip(t *testing.T) {
	path := settingsFile(t)
	settingsutil.ResetForTesting(path)
	if got := settingsutil.GetThemeColor(); got != "" {
		t.Errorf("theme color with no settings file = %q, want empty", got)
	}
	if err := settingsutil.SetAutoUpdate(true); err != nil {
		t.Fatal(err)
	}

	for _, themeColor := range []string{"teal", "#0ea5e9"} {
		if err := settingsutil.SetThemeColor(themeColor); err != nil {
			t.Fatalf("SetThemeColor(%q): %v", themeColor, err)
		}
		settingsutil.ResetForTesting(path)
		if got := settingsutil.GetThemeColor(); got != themeColor {
			t.Errorf("theme color after a reload = %q, want %q", got, themeColor)
		}
	}
	if !settingsutil.GetAutoUpdate() {
		t.Error("setting the theme color lost another setting")
	}

	if err := settingsutil.SetThemeColor("Not A Color"); !errors.Is(err, settingsutil.ErrInvalidThemeColor) {
		t.Errorf("SetThemeColor with a malformed value = %v, want ErrInvalidThemeColor", err)
	}
	if got := settingsutil.GetThemeColor(); got != "#0ea5e9" {
		t.Errorf("a refused theme color changed the stored one to %q", got)
	}

	if err := settingsutil.SetThemeColor(""); err != nil {
		t.Fatalf("clear: %v", err)
	}
	settingsutil.ResetForTesting(path)
	if got := settingsutil.GetThemeColor(); got != "" {
		t.Errorf("theme color after clearing = %q, want empty", got)
	}
}
