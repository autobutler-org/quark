package serverutil

import (
	"cmp"
	"crypto/tls"
	"net/http"
	"slices"
	"time"
)

const (
	// DefaultReadHeaderTimeout bounds the TLS handshake and the request
	// headers together: net/http applies it to both. A connection that sends
	// no ClientHello, or half a request line, is dropped after it rather than
	// holding a goroutine and its buffers forever (#2755). Ten seconds leaves a
	// phone on a poor mobile link time to finish a handshake.
	DefaultReadHeaderTimeout = 10 * time.Second
	// DefaultIdleTimeout closes a keep-alive with no request in flight. It is
	// well above the app's 15 s poll, so a polling client keeps reusing one
	// connection instead of paying a handshake each time.
	DefaultIdleTimeout = 2 * time.Minute
	// DefaultMaxHeaderBytes caps the request line and headers. A Quark
	// request carries a session cookie or bearer token and little else; the
	// net/http default of 1 MiB is far more than any client here sends.
	DefaultMaxHeaderBytes = 64 << 10
)

// NewHTTPServerParams configures NewHTTPServer. Zero values mean the
// defaults above.
type NewHTTPServerParams struct {
	Handler           http.Handler
	ReadHeaderTimeout time.Duration
	IdleTimeout       time.Duration
	MaxHeaderBytes    int
	// TLSConfig, when set, is cloned onto the server with "h2" and
	// "http/1.1" offered over ALPN, for http.Server.ServeTLS with empty cert
	// and key paths.
	TLSConfig *tls.Config
}

// NewHTTPServer builds the http.Server every Quark listener serves on, with
// header and idle timeouts and, over TLS, HTTP/2.
//
// It deliberately sets no ReadTimeout or WriteTimeout. Those are deadlines on
// the whole request and the whole response, so any value short enough to
// matter would cut off a multi-gigabyte upload or download on a slow link, and
// the events WebSocket, which stays open for as long as the app does. A
// handler that wants a deadline of its own sets one with
// http.ResponseController; none needs one today, since the header timeout is
// what closes the slowloris hole.
//
// HTTP/2 does not move the WebSocket: Go's server leaves RFC 8441 extended
// CONNECT off unless GODEBUG=http2xconnect=1, so browsers keep opening it with
// an HTTP/1.1 Upgrade, which is the only handshake github.com/coder/websocket
// accepts.
func NewHTTPServer(params NewHTTPServerParams) *http.Server {
	srv := &http.Server{
		Handler:           params.Handler,
		ReadHeaderTimeout: cmp.Or(params.ReadHeaderTimeout, DefaultReadHeaderTimeout),
		IdleTimeout:       cmp.Or(params.IdleTimeout, DefaultIdleTimeout),
		MaxHeaderBytes:    cmp.Or(params.MaxHeaderBytes, DefaultMaxHeaderBytes),
	}
	if params.TLSConfig != nil {
		cfg := params.TLSConfig.Clone()
		for _, proto := range []string{"h2", "http/1.1"} {
			if !slices.Contains(cfg.NextProtos, proto) {
				cfg.NextProtos = append(cfg.NextProtos, proto)
			}
		}
		srv.TLSConfig = cfg
	}
	return srv
}
