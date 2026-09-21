package sshutil

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"unicode"

	"golang.org/x/crypto/ssh"
)

// maxKeyLength bounds one submitted key line. A 16384-bit RSA key, the largest
// ssh-keygen makes, is under 3 KiB.
const maxKeyLength = 16 * 1024

func runCommand(ctx context.Context, stdin io.Reader, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stdin = stdin
	return cmd.CombinedOutput()
}

// runHelper runs one helper action through `sudo -n`, which fails rather than
// prompting when the sudoers entry is missing.
func runHelper(ctx context.Context, system System, stdin io.Reader, action string) error {
	if reason := system.Unavailable(); reason != ReasonNone {
		return ErrUnavailable
	}
	out, err := system.Run(ctx, stdin, "sudo", "-n", HelperPath, action)
	if err != nil {
		return fmt.Errorf("ssh-access %s: %w: %s", action, err, strings.TrimSpace(string(out)))
	}
	return nil
}

func stdinLine(s string) io.Reader {
	return strings.NewReader(s + "\n")
}

func validatePassword(password string) error {
	if len([]rune(password)) < MinPasswordLength {
		return ErrPasswordTooShort
	}
	if len(password) > MaxPasswordLength || strings.IndexFunc(password, unicode.IsControl) >= 0 {
		return ErrInvalidPassword
	}
	return nil
}

// normalizeKey parses one submitted key and returns the line to store — type,
// base64 key and comment, with any options dropped — and its description.
func normalizeKey(raw string) (string, Key, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" || len(trimmed) > maxKeyLength || strings.ContainsAny(trimmed, "\r\n") {
		return "", Key{}, ErrInvalidKey
	}
	pub, comment, _, rest, err := ssh.ParseAuthorizedKey([]byte(trimmed))
	if err != nil || len(rest) > 0 {
		return "", Key{}, ErrInvalidKey
	}
	line := strings.TrimSpace(string(ssh.MarshalAuthorizedKey(pub)))
	if comment != "" {
		line += " " + comment
	}
	return line, describeKey(pub, comment), nil
}

func describeKey(pub ssh.PublicKey, comment string) Key {
	return Key{Type: pub.Type(), Fingerprint: ssh.FingerprintSHA256(pub), Comment: comment}
}

// parseLine describes one authorized_keys line, or reports false for a blank
// line, a comment, or anything else that is not a key.
func parseLine(line string) (Key, bool) {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" || strings.HasPrefix(trimmed, "#") {
		return Key{}, false
	}
	pub, comment, _, _, err := ssh.ParseAuthorizedKey([]byte(trimmed))
	if err != nil {
		return Key{}, false
	}
	return describeKey(pub, comment), true
}

func listKeys(path string) ([]Key, error) {
	lines, err := readLines(path)
	if err != nil {
		return nil, err
	}
	keys := make([]Key, 0, len(lines))
	for _, line := range lines {
		if k, ok := parseLine(line); ok {
			keys = append(keys, k)
		}
	}
	return keys, nil
}

// readLines reads authorized_keys whole. Its size is bounded by us, not a
// user: every line in it came through AddKey. A missing file has no lines.
func readLines(path string) ([]string, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	var lines []string
	for line := range strings.SplitSeq(string(data), "\n") {
		if strings.TrimSpace(line) != "" {
			lines = append(lines, line)
		}
	}
	return lines, nil
}

// writeLines replaces authorized_keys atomically: a temp file in the same
// directory, then a rename, so sshd never reads half a file. The directory is
// 0700 and the file 0600, which sshd's StrictModes requires.
func writeLines(path string, lines []string) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("create %s: %w", dir, err)
	}
	if err := os.Chmod(dir, 0o700); err != nil {
		return fmt.Errorf("set permissions on %s: %w", dir, err)
	}
	tmp, err := os.CreateTemp(dir, ".authorized_keys-*")
	if err != nil {
		return fmt.Errorf("create temp file in %s: %w", dir, err)
	}
	defer func() { _ = os.Remove(tmp.Name()) }()
	content := ""
	if len(lines) > 0 {
		content = strings.Join(lines, "\n") + "\n"
	}
	if _, err := tmp.WriteString(content); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("write %s: %w", tmp.Name(), err)
	}
	if err := tmp.Chmod(0o600); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("set permissions on %s: %w", tmp.Name(), err)
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("sync %s: %w", tmp.Name(), err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("close %s: %w", tmp.Name(), err)
	}
	if err := os.Rename(tmp.Name(), path); err != nil {
		return fmt.Errorf("replace %s: %w", path, err)
	}
	return nil
}
