// Package hostnameutil lets an admin rename the device: it sets the system
// hostname and keeps what follows from it in step — the name Avahi answers to
// and advertises `Quark on <name>` under, and the TLS certificate's SANs
// (#2344).
//
// The service runs unprivileged, so the rename goes through one root-owned
// helper, HelperPath, which `quark install` writes along with the sudoers
// entry that lets the service run it. The helper takes no arguments: the name
// reaches it on stdin, and it checks the name again itself. Nothing here
// touches the database; the hostname lives where the OS keeps it.
package hostnameutil

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/tlsutil"
)

const (
	// HelperPath is the root-owned helper that performs the rename. It sits
	// outside the self-updatable /opt/quark/bin so the service cannot rewrite
	// what root runs.
	HelperPath = "/usr/local/libexec/quark/set-hostname"

	// MaxLength is the longest hostname accepted: one DNS label.
	MaxLength = 63
)

// Reason says why this Quark cannot be renamed.
type Reason string

const (
	// ReasonNone means the Quark can be renamed.
	ReasonNone Reason = ""
	// ReasonUnsupportedOS means the Quark is not running on Linux.
	ReasonUnsupportedOS Reason = "unsupported_os"
	// ReasonNotService means Quark is not running as its installed systemd
	// service, as the quark user, from /opt/quark/bin.
	ReasonNotService Reason = "not_service"
	// ReasonHelperMissing means `quark install` has not written HelperPath.
	ReasonHelperMissing Reason = "helper_missing"
)

var (
	// ErrUnavailable is returned by SetHostname while this Quark cannot be
	// renamed; GetHostname says why.
	ErrUnavailable = errors.New("this Quark can't be renamed")
	// ErrInvalidHostname is a name that is not one RFC 1123 label.
	ErrInvalidHostname = errors.New("hostname must be 1 to 63 lowercase letters, digits or hyphens, contain a letter, and not start or end with a hyphen")
)

// System is everything hostnameutil touches on the host, so tests can swap it.
type System struct {
	// Unavailable reports why this Quark cannot be renamed, or ReasonNone.
	Unavailable func() Reason
	// Hostname reads the system hostname.
	Hostname func() (string, error)
	// Run runs a command with stdin (which may be nil) and returns its
	// combined output. It never goes through a shell.
	Run func(ctx context.Context, stdin io.Reader, name string, args ...string) ([]byte, error)
	// RefreshCertificate regenerates the TLS certificate when it does not
	// name the current hostname.
	RefreshCertificate func() error
}

// DefaultSystem is the real host.
func DefaultSystem() System {
	return System{
		Unavailable: unavailableReason,
		Hostname:    os.Hostname,
		Run:         runCommand,
		RefreshCertificate: func() error {
			_, _, err := tlsutil.EnsureSelfSignedCert(storageutil.GetDataDir())
			return err
		},
	}
}

type GetHostnameParams struct {
	System System
}

type GetHostnameResult struct {
	// Available is whether this Quark can be renamed at all.
	Available bool
	// Reason says why not, when Available is false.
	Reason Reason
	// Hostname is the system hostname.
	Hostname string
	// AdvertisedHostname is the name Avahi answers to on the network, without
	// the .local suffix. It differs from Hostname when another device already
	// had the name: Avahi then takes the next free one, such as quark-2. It is
	// empty when Avahi does not say, and always when Available is false.
	AdvertisedHostname string
}

// GetHostname reports what this Quark is called and whether it can be
// renamed. It needs no root.
func GetHostname(ctx context.Context, params GetHostnameParams) (GetHostnameResult, error) {
	hostname, err := params.System.Hostname()
	if err != nil {
		return GetHostnameResult{}, fmt.Errorf("read hostname: %w", err)
	}
	if reason := params.System.Unavailable(); reason != ReasonNone {
		return GetHostnameResult{Reason: reason, Hostname: hostname}, nil
	}
	return GetHostnameResult{
		Available:          true,
		Hostname:           hostname,
		AdvertisedHostname: advertisedHostname(ctx, params.System),
	}, nil
}

type SetHostnameParams struct {
	System System
	// Hostname is the new name: one RFC 1123 label, already lowercase.
	Hostname string
}

type SetHostnameResult struct {
	// Hostname is the system hostname now.
	Hostname string
	// AdvertisedHostname is the name Avahi answers to once the rename is
	// done; see GetHostnameResult. Avahi notices a name another device holds
	// about a second after it starts, so a collision can show up here only on
	// a later GetHostname.
	AdvertisedHostname string
}

// SetHostname renames this Quark with no reboot: the system hostname and
// /etc/hosts, then Avahi, so <name>.local resolves and DNS-SD advertises
// `Quark on <name>`, then the TLS certificate, so it covers <name> and
// <name>.local. Clients that saved the old address have to find the Quark
// again.
func SetHostname(ctx context.Context, params SetHostnameParams) (SetHostnameResult, error) {
	if err := validateHostname(params.Hostname); err != nil {
		return SetHostnameResult{}, err
	}
	system := params.System
	if reason := system.Unavailable(); reason != ReasonNone {
		return SetHostnameResult{}, ErrUnavailable
	}
	// The helper changes several things in turn, so a caller that hangs up
	// must not stop it halfway.
	helperCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), helperTimeout)
	defer cancel()
	// `sudo -n` fails rather than prompting when the sudoers entry is missing.
	out, err := system.Run(helperCtx, strings.NewReader(params.Hostname+"\n"), "sudo", "-n", HelperPath)
	if err != nil {
		return SetHostnameResult{}, fmt.Errorf("set-hostname: %w: %s", err, strings.TrimSpace(string(out)))
	}
	// The rename is done, so a certificate that could not be regenerated is
	// not a failed rename: https://<name>.local fails verification until the
	// next start, which checks the SANs again.
	if err := system.RefreshCertificate(); err != nil {
		slog.Warn("hostname changed but the TLS certificate was not regenerated", "hostname", params.Hostname, "error", err)
	}
	return SetHostnameResult{
		Hostname:           params.Hostname,
		AdvertisedHostname: advertisedHostname(helperCtx, system),
	}, nil
}
