package tlsutil_test

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"math/big"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/tlsutil"
)

func TestEnsureSelfSignedCert_CreatesFiles(t *testing.T) {
	dir := t.TempDir()
	certFile, keyFile, err := tlsutil.EnsureSelfSignedCert(dir)
	if err != nil {
		t.Fatalf("EnsureSelfSignedCert error: %v", err)
	}

	if _, err := os.Stat(certFile); err != nil {
		t.Errorf("cert file not found: %v", err)
	}
	if _, err := os.Stat(keyFile); err != nil {
		t.Errorf("key file not found: %v", err)
	}

	// Verify cert is parseable and has adequate validity.
	certPEM, err := os.ReadFile(certFile)
	if err != nil {
		t.Fatalf("read cert: %v", err)
	}
	block, _ := pem.Decode(certPEM)
	if block == nil {
		t.Fatal("cert PEM block is nil")
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatalf("parse cert: %v", err)
	}
	if time.Until(cert.NotAfter) < 300*24*time.Hour {
		t.Errorf("cert validity too short: NotAfter=%v", cert.NotAfter)
	}
	// Confirm key type is ECDSA (P-256).
	if _, ok := cert.PublicKey.(*ecdsa.PublicKey); !ok {
		t.Errorf("expected ECDSA public key, got %T", cert.PublicKey)
	}

	// Verify key is parseable.
	keyPEM, err := os.ReadFile(keyFile)
	if err != nil {
		t.Fatalf("read key: %v", err)
	}
	keyBlock, _ := pem.Decode(keyPEM)
	if keyBlock == nil {
		t.Fatal("key PEM block is nil")
	}
	if _, err := x509.ParseECPrivateKey(keyBlock.Bytes); err != nil {
		t.Fatalf("parse EC key: %v", err)
	}
}

// The app reaches the quark by its mDNS name (e.g. https://openclaw.local), so
// that name must be a SAN or the cert never matches the URL being used.
func TestEnsureSelfSignedCert_IncludesMDNSHostname(t *testing.T) {
	hostname, err := os.Hostname()
	if err != nil || hostname == "" || hostname == "localhost" {
		t.Skip("no usable hostname on this machine")
	}

	dir := t.TempDir()
	certFile, _, err := tlsutil.EnsureSelfSignedCert(dir)
	if err != nil {
		t.Fatalf("EnsureSelfSignedCert error: %v", err)
	}

	certPEM, err := os.ReadFile(certFile)
	if err != nil {
		t.Fatalf("read cert: %v", err)
	}
	block, _ := pem.Decode(certPEM)
	if block == nil {
		t.Fatal("cert PEM block is nil")
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatalf("parse cert: %v", err)
	}

	short := strings.TrimSuffix(hostname, ".local")
	for _, want := range []string{"localhost", short, short + ".local"} {
		if !slices.Contains(cert.DNSNames, want) {
			t.Errorf("cert DNSNames %v missing %q", cert.DNSNames, want)
		}
	}
}

func TestEnsureSelfSignedCert_ReuseValid(t *testing.T) {
	dir := t.TempDir()

	certFile1, keyFile1, err := tlsutil.EnsureSelfSignedCert(dir)
	if err != nil {
		t.Fatalf("first call error: %v", err)
	}

	// Capture key bytes from first generation.
	key1, err := os.ReadFile(keyFile1)
	if err != nil {
		t.Fatalf("read key1: %v", err)
	}

	certFile2, keyFile2, err := tlsutil.EnsureSelfSignedCert(dir)
	if err != nil {
		t.Fatalf("second call error: %v", err)
	}

	if certFile1 != certFile2 || keyFile1 != keyFile2 {
		t.Error("paths changed between calls")
	}

	// Key must be identical — no regeneration should have occurred.
	key2, err := os.ReadFile(keyFile2)
	if err != nil {
		t.Fatalf("read key2: %v", err)
	}
	if string(key1) != string(key2) {
		t.Error("key was regenerated on second call even though cert was still valid")
	}
}

func TestEnsureSelfSignedCert_RegeneratesExpired(t *testing.T) {
	dir := t.TempDir()

	// Pre-populate a cert that is about to expire (within the 30-day renewal window).
	certsDir := filepath.Join(dir, "certs")
	if err := os.MkdirAll(certsDir, 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	certPath := filepath.Join(certsDir, "server.crt")
	keyPath := filepath.Join(certsDir, "server.key")
	writeSoonExpiredCert(t, certPath, keyPath)

	// Capture the key before calling EnsureSelfSignedCert.
	oldKey, err := os.ReadFile(keyPath)
	if err != nil {
		t.Fatalf("read old key: %v", err)
	}

	// EnsureSelfSignedCert must regenerate because the cert expires in 10 days.
	if _, _, err = tlsutil.EnsureSelfSignedCert(dir); err != nil {
		t.Fatalf("EnsureSelfSignedCert error: %v", err)
	}

	newKey, err := os.ReadFile(keyPath)
	if err != nil {
		t.Fatalf("read new key: %v", err)
	}
	if string(oldKey) == string(newKey) {
		t.Error("key was NOT regenerated even though cert was expiring within 30 days")
	}
}

// writeSoonExpiredCert creates a self-signed ECDSA P-256 cert that expires in
// 10 days — inside the 30-day renewal window so EnsureSelfSignedCert must
// regenerate it.
func writeSoonExpiredCert(t *testing.T, certPath, keyPath string) {
	t.Helper()

	privKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}

	now := time.Now()
	tmpl := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		NotBefore:             now.Add(-355 * 24 * time.Hour),
		NotAfter:              now.Add(10 * 24 * time.Hour), // 10 days — inside renewal window
		KeyUsage:              x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
	}

	certDER, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &privKey.PublicKey, privKey)
	if err != nil {
		t.Fatalf("create cert: %v", err)
	}

	cf, err := os.Create(certPath)
	if err != nil {
		t.Fatalf("create cert file: %v", err)
	}
	defer cf.Close()
	if err := pem.Encode(cf, &pem.Block{Type: "CERTIFICATE", Bytes: certDER}); err != nil {
		t.Fatalf("encode cert PEM: %v", err)
	}

	keyDER, err := x509.MarshalECPrivateKey(privKey)
	if err != nil {
		t.Fatalf("marshal EC key: %v", err)
	}
	kf, err := os.Create(keyPath)
	if err != nil {
		t.Fatalf("create key file: %v", err)
	}
	defer kf.Close()
	if err := pem.Encode(kf, &pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER}); err != nil {
		t.Fatalf("encode key PEM: %v", err)
	}
}

// TestEnsureSelfSignedCert_RegeneratesByReplacingWholeFiles checks a
// regenerated pair is renamed into place rather than truncating the old files
// (#2611), stays private, and still matches: a key torn by a power cut would
// never be regenerated, because only the cert decides that.
func TestEnsureSelfSignedCert_RegeneratesByReplacingWholeFiles(t *testing.T) {
	dir := t.TempDir()
	certFile, keyFile, err := tlsutil.EnsureSelfSignedCert(dir)
	if err != nil {
		t.Fatalf("first EnsureSelfSignedCert: %v", err)
	}
	oldKey, err := os.ReadFile(keyFile)
	if err != nil {
		t.Fatalf("read key: %v", err)
	}
	if err := os.Link(keyFile, keyFile+".old"); err != nil {
		t.Fatalf("link key: %v", err)
	}
	if err := os.WriteFile(certFile, []byte("not a cert"), 0o600); err != nil {
		t.Fatalf("corrupt cert: %v", err)
	}

	if _, _, err := tlsutil.EnsureSelfSignedCert(dir); err != nil {
		t.Fatalf("second EnsureSelfSignedCert: %v", err)
	}

	linked, err := os.ReadFile(keyFile + ".old")
	if err != nil {
		t.Fatalf("read old key link: %v", err)
	}
	if string(linked) != string(oldKey) {
		t.Fatal("key was rewritten in place; a power cut mid-write could leave it empty")
	}
	if _, err := tls.LoadX509KeyPair(certFile, keyFile); err != nil {
		t.Fatalf("regenerated pair does not load: %v", err)
	}
	for _, f := range []string{certFile, keyFile} {
		info, err := os.Stat(f)
		if err != nil {
			t.Fatalf("stat %s: %v", f, err)
		}
		if perm := info.Mode().Perm(); perm != 0o600 {
			t.Errorf("%s mode = %o, want 600", filepath.Base(f), perm)
		}
	}
}
