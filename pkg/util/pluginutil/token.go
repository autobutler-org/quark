package pluginutil

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	vfsTokenDuration = time.Hour
	signingKeySize   = 32 // bytes
)

// tokenSigner holds the host-internal JWT signing key for VFS plugin tokens.
// The key is generated fresh at startup; tokens from previous runs are
// immediately invalid.
var tokenSigner = &pluginTokenSigner{}

type pluginTokenSigner struct {
	mu  sync.RWMutex
	key []byte
}

func init() {
	if err := tokenSigner.rotate(); err != nil {
		panic(fmt.Sprintf("pluginutil: failed to generate initial VFS signing key: %v", err))
	}
}

// rotate replaces the signing key. Old tokens signed with the previous key
// are immediately rejected (there is no key-ID or rotation grace period —
// plugins are restarted on rotate, which re-issues new tokens).
func (s *pluginTokenSigner) rotate() error {
	key := make([]byte, signingKeySize)
	if _, err := rand.Read(key); err != nil {
		return err
	}
	s.mu.Lock()
	s.key = key
	s.mu.Unlock()
	return nil
}

func (s *pluginTokenSigner) sign(claims jwt.Claims) (string, error) {
	s.mu.RLock()
	key := s.key
	s.mu.RUnlock()
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return tok.SignedString(key)
}

func (s *pluginTokenSigner) parse(tokenStr string, claims jwt.Claims) (*jwt.Token, error) {
	s.mu.RLock()
	key := s.key
	s.mu.RUnlock()
	return jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return key, nil
	})
}

// VFSClaims are the JWT claims embedded in a plugin VFS token.
type VFSClaims struct {
	jwt.RegisteredClaims
	PluginID        string   `json:"plugin_id"`
	NamespacesRead  []string `json:"ns_read,omitempty"`
	NamespacesWrite []string `json:"ns_write,omitempty"`
}

// IssueVFSToken creates a scoped, short-lived JWT for a plugin subprocess.
// The token encodes the plugin's permitted namespace access and expires in 1 hour.
func IssueVFSToken(pluginID string, nsRead, nsWrite []string) (string, error) {
	now := time.Now()
	claims := VFSClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   pluginID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(vfsTokenDuration)),
		},
		PluginID:        pluginID,
		NamespacesRead:  nsRead,
		NamespacesWrite: nsWrite,
	}
	return tokenSigner.sign(claims)
}

// ValidateVFSToken parses and validates a plugin VFS token.
// Returns the decoded VFSClaims on success.
func ValidateVFSToken(tokenStr string) (*VFSClaims, error) {
	claims := &VFSClaims{}
	tok, err := tokenSigner.parse(tokenStr, claims)
	if err != nil || !tok.Valid {
		return nil, fmt.Errorf("invalid plugin VFS token: %w", err)
	}
	return claims, nil
}

// RotateSigningKey replaces the VFS signing key and returns a new raw hex key
// for logging/audit purposes. All existing plugin tokens are immediately
// invalidated; callers must restart plugins to re-issue tokens.
func RotateSigningKey() error {
	return tokenSigner.rotate()
}

// randomHex generates n bytes of cryptographic randomness as a hex string.
func randomHex(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
