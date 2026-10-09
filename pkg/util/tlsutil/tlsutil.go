// Package tlsutil provides helpers for provisioning self-signed TLS certificates
// used by the Quark server when running in production (HTTPS) mode.
package tlsutil

import (
	"crypto/tls"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"
	"time"
)

const (
	renewalWindow = 30 * 24 * time.Hour // Regenerate if cert expires within 30 days.
	certValidity  = 365 * 24 * time.Hour
)

// EnsureSelfSignedCert checks if certFile/keyFile exist and are valid: not expiring soon,
// and naming this host. If absent, expiring within 30 days, or made under another
// hostname, it generates a new ECDSA P-256 self-signed cert
// valid for 365 days with SANs for localhost, the machine's own hostname and its
// .local mDNS name, 127.0.0.1, ::1, and any local network IPs.
// Cert and key are stored at dataDir/certs/server.crt and server.key.
// Returns the paths to the cert and key files.
func EnsureSelfSignedCert(dataDir string) (certFile, keyFile string, err error) {
	certsDir := filepath.Join(dataDir, "certs")
	certFile = filepath.Join(certsDir, "server.crt")
	keyFile = filepath.Join(certsDir, "server.key")

	if needsRegen(certFile) {
		log.Printf("[tlsutil] generating new self-signed TLS certificate in %s", certsDir)
		if err = os.MkdirAll(certsDir, 0o700); err != nil {
			return "", "", fmt.Errorf("tlsutil: create certs dir: %w", err)
		}
		if err = generate(certFile, keyFile); err != nil {
			return "", "", fmt.Errorf("tlsutil: generate cert: %w", err)
		}
		log.Printf("[tlsutil] self-signed cert written to %s", certFile)
	} else {
		log.Printf("[tlsutil] reusing existing TLS certificate at %s", certFile)
	}

	return certFile, keyFile, nil
}

// CertificateGetter returns a tls.Config.GetCertificate that serves the pair
// at certFile and keyFile, and loads it again whenever certFile changes on
// disk. A certificate EnsureSelfSignedCert regenerates while the server runs,
// as a rename does (#2344), then reaches new connections without a restart.
// It fails only when the pair cannot be loaded at all; a later pair that does
// not load leaves the last good one in place.
func CertificateGetter(certFile, keyFile string) (func(*tls.ClientHelloInfo) (*tls.Certificate, error), error) {
	var (
		mu      sync.Mutex
		current *tls.Certificate
		modTime time.Time
	)
	get := func(*tls.ClientHelloInfo) (*tls.Certificate, error) {
		mu.Lock()
		defer mu.Unlock()
		// generate renames the key into place before the cert, so a new cert
		// on disk always has its key beside it.
		info, err := os.Stat(certFile)
		if err == nil && (current == nil || !info.ModTime().Equal(modTime)) {
			var loaded tls.Certificate
			if loaded, err = tls.LoadX509KeyPair(certFile, keyFile); err == nil {
				current, modTime = &loaded, info.ModTime()
			}
		}
		if current == nil {
			return nil, fmt.Errorf("tlsutil: load certificate: %w", err)
		}
		return current, nil
	}
	if _, err := get(nil); err != nil {
		return nil, err
	}
	return get, nil
}
