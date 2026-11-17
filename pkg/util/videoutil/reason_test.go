package videoutil

import (
	"context"
	"errors"
	"io"
	"syscall"
	"testing"
	"time"
)

// TestReasonOf is #3423's shared source of truth: every way a video the user
// has fails to read or trim names one cause, and a failure that is not about
// the file names none.
func TestReasonOf(t *testing.T) {
	probeErr := func(file func(*testing.T) string) func(*testing.T) error {
		return func(t *testing.T) error {
			_, err := ProbeSource(context.Background(), openFixture(t, file(t)))
			return err
		}
	}
	trimErr := func(file func(*testing.T) string) func(*testing.T) error {
		return func(t *testing.T) error {
			_, err := Trim(context.Background(), TrimParams{Source: openFixture(t, file(t)), Output: io.Discard, End: time.Second})
			return err
		}
	}
	cases := []struct {
		name string
		err  func(*testing.T) error
		want Reason
	}{
		{"an AVI", probeErr(fixture(aviFixture)), ReasonUnsupportedFormat},
		{"bytes that are not a video", probeErr(notAVideo), ReasonUnsupportedFormat},
		{"a truncated MP4", probeErr(truncatedClip), ReasonDamaged},
		{"trimming a truncated MP4", trimErr(truncatedClip), ReasonDamaged},
		{"trimming a fragmented MP4", trimErr(fixture(fragmentedFixture)), ReasonFragmented},
		{"trimming an MPEG-TS file", trimErr(fixture(tsFixture)), ReasonCannotTrim},
		{"a read the disk failed", func(*testing.T) error { return syscall.EIO }, ReasonNone},
		{"no error", func(*testing.T) error { return nil }, ReasonNone},
		{"an error that is not about the file", func(*testing.T) error { return errors.New("boom") }, ReasonNone},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := c.err(t)
			if got := ReasonOf(err); got != c.want {
				t.Errorf("ReasonOf(%v) = %q, want %q", err, got, c.want)
			}
		})
	}
}
