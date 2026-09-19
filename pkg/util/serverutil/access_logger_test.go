package serverutil

import "testing"

func TestRedactQuery(t *testing.T) {
	cases := []struct {
		name, in, want string
	}{
		{"no query", "/api/v0/files", "/api/v0/files"},
		{"token alone", "/api/v0/videos/stream?token=hunter2", "/api/v0/videos/stream?token=REDACTED"},
		{
			"token among others keeps their order and encoding",
			"/api/v0/files/download?filePath=a%20b.mp4&token=hunter2&serial=X1",
			"/api/v0/files/download?filePath=a%20b.mp4&token=REDACTED&serial=X1",
		},
		{"every copy of the token", "/x?token=a&token=b", "/x?token=REDACTED&token=REDACTED"},
		{"an empty token", "/x?token=", "/x?token=REDACTED"},
		{"a bare token key", "/x?token", "/x?token=REDACTED"},
		{"a percent-encoded key", "/x?%74%6F%6B%65%6E=hunter2", "/x?%74%6F%6B%65%6E=REDACTED"},
		{"a parameter that only starts with token", "/x?tokens=1", "/x?tokens=1"},
		{"a token value on another key", "/x?q=token", "/x?q=token"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := redactQuery(tc.in); got != tc.want {
				t.Errorf("redactQuery(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}
