package hostnameutil

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"os/exec"
	"time"
)

const (
	// helperTimeout bounds the whole rename: the hostname, then an Avahi restart.
	helperTimeout = 30 * time.Second
	// avahiTimeout bounds asking Avahi for its name, which is one D-Bus call.
	avahiTimeout = 3 * time.Second
)

func runCommand(ctx context.Context, stdin io.Reader, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stdin = stdin
	return cmd.CombinedOutput()
}

// validateHostname accepts one RFC 1123 label, lowercase only: letters,
// digits and hyphens, 1 to MaxLength long, no hyphen at either end. The root
// helper applies the same rules again, since it is the one sudo trusts. Two
// names that fit the label are refused as well: a bare number, which resolvers
// read as an IP address, and localhost.
func validateHostname(name string) error {
	if name == "" || len(name) > MaxLength || name == "localhost" {
		return ErrInvalidHostname
	}
	if name[0] == '-' || name[len(name)-1] == '-' {
		return ErrInvalidHostname
	}
	hasLetter := false
	for i := 0; i < len(name); i++ {
		c := name[i]
		switch {
		case c >= 'a' && c <= 'z':
			hasLetter = true
		case c >= '0' && c <= '9', c == '-':
		default:
			return ErrInvalidHostname
		}
	}
	if !hasLetter {
		return ErrInvalidHostname
	}
	return nil
}

// advertisedHostname asks Avahi over D-Bus which name it answers to, or
// returns "" when it does not say: Avahi is not installed or not running.
// Any account may make this call, and --auto-start=no keeps it from starting
// a stopped daemon. busctl ships with systemd, so it needs no avahi-utils.
func advertisedHostname(ctx context.Context, system System) string {
	ctx, cancel := context.WithTimeout(ctx, avahiTimeout)
	defer cancel()
	out, err := system.Run(ctx, nil, "busctl", "--system", "--auto-start=no", "--json=short",
		"call", "org.freedesktop.Avahi", "/", "org.freedesktop.Avahi.Server", "GetHostName")
	if err != nil {
		return ""
	}
	var reply struct {
		Data []string `json:"data"`
	}
	if err := json.Unmarshal(bytes.TrimSpace(out), &reply); err != nil || len(reply.Data) != 1 {
		return ""
	}
	return reply.Data[0]
}
