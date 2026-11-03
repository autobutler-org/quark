package server

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/tlsutil"
)

// quark serve --tls-cert/--tls-key serves the operator's pair and writes no
// self-signed one under the data dir (#1141).
func TestCertificateGetter_OperatorPairWritesNothingToTheDataDir(t *testing.T) {
	certFile, keyFile, err := tlsutil.EnsureSelfSignedCert(t.TempDir())
	if err != nil {
		t.Fatalf("EnsureSelfSignedCert: %v", err)
	}
	dataDir := t.TempDir()
	get, served, err := certificateGetter(StartOptions{TLSCert: certFile, TLSKey: keyFile}, dataDir)
	if err != nil {
		t.Fatalf("certificateGetter: %v", err)
	}
	if served != certFile {
		t.Errorf("serving %s, want %s", served, certFile)
	}
	if _, err := get(nil); err != nil {
		t.Errorf("get: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dataDir, "certs")); !os.IsNotExist(err) {
		t.Errorf("<dataDir>/certs exists (stat err %v); an operator pair must not write one", err)
	}
}

func TestCertificateGetter_RejectsBadFlags(t *testing.T) {
	certFile, keyFile, err := tlsutil.EnsureSelfSignedCert(t.TempDir())
	if err != nil {
		t.Fatalf("EnsureSelfSignedCert: %v", err)
	}
	_, otherKey, err := tlsutil.EnsureSelfSignedCert(t.TempDir())
	if err != nil {
		t.Fatalf("EnsureSelfSignedCert: %v", err)
	}
	for name, tc := range map[string]struct {
		opts StartOptions
		want string
	}{
		"cert without key":     {StartOptions{TLSCert: certFile}, "--tls-cert is set without --tls-key"},
		"key without cert":     {StartOptions{TLSKey: keyFile}, "--tls-key is set without --tls-cert"},
		"insecure with a pair": {StartOptions{Insecure: true, TLSCert: certFile, TLSKey: keyFile}, "--insecure"},
		"mismatched pair":      {StartOptions{TLSCert: certFile, TLSKey: otherKey}, "--tls-cert " + certFile},
	} {
		t.Run(name, func(t *testing.T) {
			_, _, err := certificateGetter(tc.opts, t.TempDir())
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Errorf("err = %v, want it to mention %q", err, tc.want)
			}
		})
	}
}
