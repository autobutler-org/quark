// Package sshutil lets an admin turn SSH access to the Quark on and off, and
// manage how the quark login account signs in: public keys and an optional
// password (#2131).
//
// The service runs unprivileged, so everything that needs root goes through
// one root-owned helper, HelperPath, which `quark install` writes along with
// the one sudoers entry that lets the service run it. Keys live in a file the
// service owns, AuthorizedKeysPath, which the sshd drop-in `quark install`
// writes points sshd at. Nothing here touches the database, and the password
// is never stored: it goes straight to the helper on stdin.
package sshutil

import (
	"context"
	"errors"
	"io"
)

const (
	// HelperPath is the root-owned helper that performs the privileged steps.
	// It sits outside the self-updatable /opt/quark/bin so the service cannot
	// rewrite what root runs.
	HelperPath = "/usr/local/libexec/quark/ssh-access"

	// AuthorizedKeysPath holds the public keys allowed to sign in as quark.
	// It lives under the service's own data directory so the service can edit
	// it without root, whether or not the account has a home directory.
	AuthorizedKeysPath = "/var/lib/quark/.ssh/authorized_keys"

	// LoginUser is the only account SSH lets in.
	LoginUser = "quark"

	// MinPasswordLength is the shortest login password accepted. Longer than
	// an app password, since this one guards a shell reachable on the network.
	MinPasswordLength = 12

	// MaxPasswordLength bounds what is piped to chpasswd.
	MaxPasswordLength = 1024
)

// Reason says why SSH access cannot be managed on this Quark.
type Reason string

const (
	// ReasonNone means SSH access can be managed.
	ReasonNone Reason = ""
	// ReasonUnsupportedOS means the Quark is not running on Linux.
	ReasonUnsupportedOS Reason = "unsupported_os"
	// ReasonNotService means Quark is not running as its installed systemd
	// service, as the quark user, from /opt/quark/bin.
	ReasonNotService Reason = "not_service"
	// ReasonSSHDMissing means the OpenSSH server is not installed.
	ReasonSSHDMissing Reason = "sshd_missing"
	// ReasonHelperMissing means `quark install` has not written HelperPath.
	ReasonHelperMissing Reason = "helper_missing"
	// ReasonNoLoginShell means the quark account's shell refuses logins.
	ReasonNoLoginShell Reason = "no_login_shell"
)

var (
	// ErrUnavailable is returned by every change while SSH access cannot be
	// managed; GetStatus says why.
	ErrUnavailable = errors.New("SSH access can't be managed on this Quark")
	// ErrInvalidKey is a key that is not one OpenSSH public key.
	ErrInvalidKey = errors.New("that is not an SSH public key")
	// ErrKeyExists is a key that is already allowed.
	ErrKeyExists = errors.New("that key is already allowed")
	// ErrKeyNotFound is a fingerprint no allowed key has.
	ErrKeyNotFound = errors.New("no allowed key has that fingerprint")
	// ErrPasswordTooShort is a password under MinPasswordLength characters.
	ErrPasswordTooShort = errors.New("password must be at least 12 characters")
	// ErrInvalidPassword is a password too long or holding control characters.
	ErrInvalidPassword = errors.New("password is too long or contains control characters")
)

// System is everything sshutil touches on the host, so tests can swap it.
type System struct {
	// Unavailable reports why SSH access cannot be managed, or ReasonNone.
	Unavailable func() Reason
	// Run runs a command with stdin (which may be nil) and returns its
	// combined output.
	Run func(ctx context.Context, stdin io.Reader, name string, args ...string) ([]byte, error)
	// AuthorizedKeysPath is the authorized_keys file to manage.
	AuthorizedKeysPath string
}

// DefaultSystem is the real host.
func DefaultSystem() System {
	return System{
		Unavailable:        unavailableReason,
		Run:                runCommand,
		AuthorizedKeysPath: AuthorizedKeysPath,
	}
}

// Key is one public key allowed to sign in.
type Key struct {
	// Type is the key algorithm, such as ssh-ed25519.
	Type string `json:"type"`
	// Fingerprint is the SHA256 fingerprint, as `ssh-keygen -l` prints it.
	Fingerprint string `json:"fingerprint"`
	// Comment is the text after the key, often user@host. May be empty.
	Comment string `json:"comment"`
}

type GetStatusParams struct {
	System System
}

type GetStatusResult struct {
	// Available is whether SSH access can be managed here at all.
	Available bool
	// Reason says why not, when Available is false.
	Reason Reason
	// Enabled is whether sshd is running now.
	Enabled bool
	// Keys are the public keys allowed to sign in.
	Keys []Key
}

// GetStatus reports whether SSH access is on, and who may sign in. It needs no
// root. Whether a password is set is not reported: reading that takes root.
func GetStatus(ctx context.Context, params GetStatusParams) (GetStatusResult, error) {
	if reason := params.System.Unavailable(); reason != ReasonNone {
		return GetStatusResult{Reason: reason}, nil
	}
	keys, err := listKeys(params.System.AuthorizedKeysPath)
	if err != nil {
		return GetStatusResult{}, err
	}
	// is-active succeeds when either unit is active; the socket counts, since
	// socket activation is how some Debian releases run sshd.
	_, activeErr := params.System.Run(ctx, nil, "systemctl", "is-active", "--quiet", "ssh.service", "ssh.socket")
	return GetStatusResult{Available: true, Enabled: activeErr == nil, Keys: keys}, nil
}

type SetEnabledParams struct {
	System  System
	Enabled bool
}

type SetEnabledResult struct{}

// SetEnabled starts sshd and opens port 22, or stops it and closes the port.
// Either way the choice survives a reboot.
func SetEnabled(ctx context.Context, params SetEnabledParams) (SetEnabledResult, error) {
	action := "disable"
	if params.Enabled {
		action = "enable"
	}
	return SetEnabledResult{}, runHelper(ctx, params.System, nil, action)
}

type AddKeyParams struct {
	System System
	// Key is one line in authorized_keys format: type, base64 key, comment.
	Key string
}

type AddKeyResult struct {
	Key Key
}

// AddKey allows a public key to sign in. Options such as command= are not
// accepted; the key is stored as its type, key and comment only.
func AddKey(params AddKeyParams) (AddKeyResult, error) {
	if reason := params.System.Unavailable(); reason != ReasonNone {
		return AddKeyResult{}, ErrUnavailable
	}
	line, key, err := normalizeKey(params.Key)
	if err != nil {
		return AddKeyResult{}, err
	}
	lines, err := readLines(params.System.AuthorizedKeysPath)
	if err != nil {
		return AddKeyResult{}, err
	}
	for _, existing := range lines {
		if k, ok := parseLine(existing); ok && k.Fingerprint == key.Fingerprint {
			return AddKeyResult{}, ErrKeyExists
		}
	}
	if err := writeLines(params.System.AuthorizedKeysPath, append(lines, line)); err != nil {
		return AddKeyResult{}, err
	}
	return AddKeyResult{Key: key}, nil
}

type RemoveKeyParams struct {
	System      System
	Fingerprint string
}

type RemoveKeyResult struct{}

// RemoveKey stops the key with Fingerprint from signing in.
func RemoveKey(params RemoveKeyParams) (RemoveKeyResult, error) {
	if reason := params.System.Unavailable(); reason != ReasonNone {
		return RemoveKeyResult{}, ErrUnavailable
	}
	lines, err := readLines(params.System.AuthorizedKeysPath)
	if err != nil {
		return RemoveKeyResult{}, err
	}
	kept := make([]string, 0, len(lines))
	for _, line := range lines {
		if k, ok := parseLine(line); ok && k.Fingerprint == params.Fingerprint {
			continue
		}
		kept = append(kept, line)
	}
	if len(kept) == len(lines) {
		return RemoveKeyResult{}, ErrKeyNotFound
	}
	return RemoveKeyResult{}, writeLines(params.System.AuthorizedKeysPath, kept)
}

type SetPasswordParams struct {
	System   System
	Password string
}

type SetPasswordResult struct{}

// SetPassword sets the quark login account's password. It goes to the helper
// on stdin, never on a command line, and is not stored or logged.
func SetPassword(ctx context.Context, params SetPasswordParams) (SetPasswordResult, error) {
	if err := validatePassword(params.Password); err != nil {
		return SetPasswordResult{}, err
	}
	return SetPasswordResult{}, runHelper(ctx, params.System, stdinLine(params.Password), "set-password")
}

type ClearPasswordParams struct {
	System System
}

type ClearPasswordResult struct{}

// ClearPassword removes the quark login account's password, so only keys can
// sign in.
func ClearPassword(ctx context.Context, params ClearPasswordParams) (ClearPasswordResult, error) {
	return ClearPasswordResult{}, runHelper(ctx, params.System, nil, "clear-password")
}
