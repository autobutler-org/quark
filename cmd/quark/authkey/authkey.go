// Package authkey is the quark auth-key subcommand, which derives the auth key a script signs in to a Quark with
// (#2713): it fetches the account's salt, derives the key on this machine, and prints it.
package authkey

import (
	"bufio"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/autobutler-org/quark/pkg/util/authutil"

	"github.com/spf13/cobra"
	"golang.org/x/term"
)

// Cmd is quark auth-key. The key goes to stdout alone, so $(quark auth-key ...) holds nothing else; the prompt,
// notes and errors go to stderr.
func Cmd() *cobra.Command {
	var host, username string
	var recovery, insecure bool
	cmd := &cobra.Command{
		Use:   "auth-key --host <url> -u <username>",
		Short: "Derive the auth key a script signs in to a Quark with",
		Long: `A Quark never takes a password: a client sends the auth key derived from it.
auth-key asks the Quark at --host for the account's salt, derives the key on
this machine, and prints it. The password is never sent anywhere.

The password is asked for without echo, or read from stdin when stdin is not a
terminal. It is never a flag, which would leave it in shell history and ps.

The key is what a script sends as authKey to /api/v0/auth/login, and as the
password of HTTP Basic. With --recovery the secret is the recovery phrase and
the key is the recoveryKey that /api/v0/auth/recover takes.`,
		Example: `  quark auth-key --host https://quark.local -u ada

  # Sign in from a script
  KEY="$(quark auth-key --host "$Q" -u "$U")"
  curl -H 'Content-Type: application/json' \
    -d "{\"username\":\"$U\",\"authKey\":\"$KEY\"}" "$Q/api/v0/auth/login"

  # HTTP Basic, the password read from a file
  curl -u "$U:$(quark auth-key --host "$Q" -u "$U" < password.txt)" "$Q/api/v0/files"`,
		Args:         cobra.NoArgs,
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, _ []string) error {
			if cmd.Flags().NFlag() == 0 {
				return cmd.Help()
			}
			if !strings.HasPrefix(host, "http://") && !strings.HasPrefix(host, "https://") {
				return fmt.Errorf("--host %q is not a URL: pass the Quark's address with its scheme, like https://quark.local or http://localhost:8080", host)
			}
			if username == "" {
				return errors.New("no username: pass the account's with -u")
			}

			// The salt comes first, so a wrong host fails before anything is typed.
			salt, err := fetchSalt(strings.TrimRight(host, "/"), username, insecure)
			if err != nil {
				return err
			}
			if note := salt.note(recovery); note != "" {
				_, _ = fmt.Fprintln(cmd.ErrOrStderr(), "note:", note)
			}

			what := "Password"
			if recovery {
				what = "Recovery phrase"
			}
			secret, err := readSecret(cmd.InOrStdin(), cmd.ErrOrStderr(), what+" for "+username+": ")
			if err != nil {
				return err
			}
			if secret == "" {
				return fmt.Errorf("no %s given: type it at the prompt, or pipe it in on stdin", strings.ToLower(what))
			}

			result, err := authutil.DeriveKey(authutil.DeriveKeyParams{Secret: secret, Salt: salt.Salt, Recovery: recovery})
			if err != nil {
				return err
			}
			_, err = fmt.Fprintln(cmd.OutOrStdout(), result.Key)
			return err
		},
	}
	cmd.Flags().StringVar(&host, "host", "", "the Quark's address, like https://quark.local")
	cmd.Flags().StringVarP(&username, "username", "u", "", "the account to derive the key for")
	cmd.Flags().BoolVar(&recovery, "recovery", false, "derive the recovery key from the recovery phrase instead")
	cmd.Flags().BoolVarP(&insecure, "insecure", "k", false, "skip the certificate check, as curl -k does, for a self-signed Quark")
	return cmd
}

// saltAnswer is what GET /api/v0/auth/salt answers.
type saltAnswer struct {
	Salt           string `json:"salt"`
	Legacy         bool   `json:"legacy"`
	LegacyRecovery bool   `json:"legacyRecovery"`
}

// note is what to tell the user about an account the derived key will not work for alone, or "".
func (s saltAnswer) note(recovery bool) string {
	switch {
	case recovery && s.LegacyRecovery:
		return "this account has no recovery key yet, so the Quark will refuse this one; sign in with the app once to give it one"
	case !recovery && s.Legacy:
		return "this account has not moved to auth keys, so this key alone is refused; sign in with the app once, or send the password beside it once as docs/auth.md shows"
	}
	return ""
}

// fetchSalt asks the Quark at base for username's salt. Every failure says which URL it was and what to do next.
func fetchSalt(base, username string, insecure bool) (saltAnswer, error) {
	endpoint := base + "/api/v0/auth/salt?username=" + url.QueryEscape(username)
	client := &http.Client{Timeout: 15 * time.Second}
	if insecure {
		client.Transport = &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}
	}
	resp, err := client.Get(endpoint)
	if err != nil {
		// A url.Error repeats the URL the messages below already name.
		if wrapped, ok := errors.AsType[*url.Error](err); ok {
			err = wrapped.Err
		}
		if _, untrusted := errors.AsType[*tls.CertificateVerificationError](err); untrusted {
			return saltAnswer{}, fmt.Errorf("%s has a certificate this machine does not trust: %w\nA Quark's own certificate is self-signed; pass -k to skip the check, as curl -k does", base, err)
		}
		return saltAnswer{}, fmt.Errorf("could not reach %s: %w\nCheck that the Quark is on and --host is its address: curl %s/api/v0/auth/status", endpoint, err, base)
	}
	defer func() { _ = resp.Body.Close() }()

	switch resp.StatusCode {
	case http.StatusOK:
	case http.StatusNotFound:
		return saltAnswer{}, fmt.Errorf("%s answered 404: this Quark is from before auth keys and has no salt endpoint\nUpdate the Quark, then run this again", endpoint)
	case http.StatusTooManyRequests:
		return saltAnswer{}, fmt.Errorf("%s answered 429: too many requests from this address\nWait a minute, then run this again", endpoint)
	default:
		return saltAnswer{}, fmt.Errorf("%s answered %d\nCheck that --host is a Quark: curl %s/api/v0/auth/status", endpoint, resp.StatusCode, base)
	}
	var answer saltAnswer
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&answer); err != nil || answer.Salt == "" {
		return saltAnswer{}, fmt.Errorf("%s did not answer with a salt\nCheck that --host is a Quark, and update it if it is an old one: curl %s/api/v0/auth/status", endpoint, base)
	}
	return answer, nil
}

// readSecret reads the password or phrase: from a prompt with no echo when in is a terminal, and otherwise the
// first line of in, so a pipe or a file can feed it.
func readSecret(in io.Reader, errOut io.Writer, prompt string) (string, error) {
	if file, ok := in.(*os.File); ok && term.IsTerminal(int(file.Fd())) {
		_, _ = fmt.Fprint(errOut, prompt)
		secret, err := term.ReadPassword(int(file.Fd()))
		_, _ = fmt.Fprintln(errOut)
		if err != nil {
			return "", fmt.Errorf("read the prompt: %w", err)
		}
		return string(secret), nil
	}
	line, err := bufio.NewReader(io.LimitReader(in, 1<<16)).ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return "", fmt.Errorf("read stdin: %w", err)
	}
	return strings.TrimRight(line, "\r\n"), nil
}
