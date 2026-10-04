package serverutil

import (
	"bufio"
	"crypto/tls"
	"errors"
	"io"
	"net"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/tlsutil"
)

// startServer serves srv on a loopback listener, over TLS when tlsCfg is set,
// and returns the address.
func startServer(t *testing.T, srv *http.Server, useTLS bool) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	go func() {
		if useTLS {
			_ = srv.ServeTLS(ln, "", "")
		} else {
			_ = srv.Serve(ln)
		}
	}()
	t.Cleanup(func() { _ = srv.Close() })
	return ln.Addr().String()
}

// closedWithin reports whether the server closes conn within d. A read that
// returns EOF or a reset is a close; a read deadline expiring first is not.
func closedWithin(t *testing.T, conn net.Conn, d time.Duration) bool {
	t.Helper()
	if err := conn.SetReadDeadline(time.Now().Add(d)); err != nil {
		t.Fatalf("set deadline: %v", err)
	}
	_, err := io.Copy(io.Discard, conn)
	var netErr net.Error
	if errors.As(err, &netErr) && netErr.Timeout() {
		return false
	}
	return true
}

func testCert(t *testing.T) tls.Certificate {
	t.Helper()
	certFile, keyFile, err := tlsutil.EnsureSelfSignedCert(t.TempDir())
	if err != nil {
		t.Fatalf("EnsureSelfSignedCert: %v", err)
	}
	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		t.Fatalf("LoadX509KeyPair: %v", err)
	}
	return cert
}

func okHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { _, _ = io.WriteString(w, "ok") })
}

// TestNewHTTPServer_Defaults pins the limits #2755 asks for, and pins that no
// whole-request deadline is set: a ReadTimeout or WriteTimeout would cut off a
// large upload, a large download and the events WebSocket.
func TestNewHTTPServer_Defaults(t *testing.T) {
	srv := NewHTTPServer(NewHTTPServerParams{Handler: okHandler()})
	if srv.ReadHeaderTimeout != DefaultReadHeaderTimeout || srv.ReadHeaderTimeout <= 0 {
		t.Errorf("ReadHeaderTimeout = %v; want %v", srv.ReadHeaderTimeout, DefaultReadHeaderTimeout)
	}
	// The app polls every 15 s; an idle timeout shorter than that would make
	// every poll pay a new handshake.
	if srv.IdleTimeout != DefaultIdleTimeout || srv.IdleTimeout <= 15*time.Second {
		t.Errorf("IdleTimeout = %v; want %v, longer than the app's 15 s poll", srv.IdleTimeout, DefaultIdleTimeout)
	}
	if srv.MaxHeaderBytes != DefaultMaxHeaderBytes {
		t.Errorf("MaxHeaderBytes = %d; want %d", srv.MaxHeaderBytes, DefaultMaxHeaderBytes)
	}
	if srv.ReadTimeout != 0 || srv.WriteTimeout != 0 {
		t.Errorf("ReadTimeout = %v, WriteTimeout = %v; want both unset so streams are not cut off",
			srv.ReadTimeout, srv.WriteTimeout)
	}
}

// TestNewHTTPServer_ClosesStalledHeaders is the slowloris case: a client that
// sends half a request line and then nothing is dropped after the header
// timeout instead of holding a goroutine forever.
func TestNewHTTPServer_ClosesStalledHeaders(t *testing.T) {
	addr := startServer(t, NewHTTPServer(NewHTTPServerParams{
		Handler: okHandler(), ReadHeaderTimeout: 200 * time.Millisecond,
	}), false)
	conn, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer conn.Close()
	if _, err := io.WriteString(conn, "GET / HTTP/1.1\r\nHost: x\r\n"); err != nil {
		t.Fatalf("write: %v", err)
	}
	if !closedWithin(t, conn, 3*time.Second) {
		t.Fatal("server kept a connection with unfinished headers open; want it closed after ReadHeaderTimeout")
	}
}

// TestNewHTTPServer_ClosesStalledTLSHandshake covers `nc <quark> 443`: a TCP
// connection that never sends its ClientHello. net/http bounds the handshake by
// the header timeout.
func TestNewHTTPServer_ClosesStalledTLSHandshake(t *testing.T) {
	addr := startServer(t, NewHTTPServer(NewHTTPServerParams{
		Handler:           okHandler(),
		ReadHeaderTimeout: 200 * time.Millisecond,
		TLSConfig:         &tls.Config{Certificates: []tls.Certificate{testCert(t)}, MinVersion: tls.VersionTLS13},
	}), true)
	conn, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer conn.Close()
	if !closedWithin(t, conn, 3*time.Second) {
		t.Fatal("server kept a connection that never sent a ClientHello open")
	}
}

// TestNewHTTPServer_ClosesIdleKeepAlive verifies an idle keep-alive is closed
// after the idle timeout rather than living until the client drops it.
func TestNewHTTPServer_ClosesIdleKeepAlive(t *testing.T) {
	addr := startServer(t, NewHTTPServer(NewHTTPServerParams{
		Handler: okHandler(), IdleTimeout: 200 * time.Millisecond,
	}), false)
	conn, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer conn.Close()
	if _, err := io.WriteString(conn, "GET / HTTP/1.1\r\nHost: x\r\n\r\n"); err != nil {
		t.Fatalf("write: %v", err)
	}
	resp, err := http.ReadResponse(bufio.NewReader(conn), nil)
	if err != nil {
		t.Fatalf("read response: %v", err)
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	_ = resp.Body.Close()
	if !closedWithin(t, conn, 3*time.Second) {
		t.Fatal("server kept an idle keep-alive open; want it closed after IdleTimeout")
	}
}

// TestNewHTTPServer_SlowBodyOutlivesHeaderTimeout proves the header timeout is
// not a whole-request deadline: a body that trickles in for several header
// timeouts, as a large upload on a slow link does, still arrives whole.
func TestNewHTTPServer_SlowBodyOutlivesHeaderTimeout(t *testing.T) {
	const timeout = 100 * time.Millisecond
	addr := startServer(t, NewHTTPServer(NewHTTPServerParams{
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			n, _ := io.Copy(io.Discard, r.Body)
			_, _ = io.WriteString(w, strings.Repeat("x", int(n)))
		}),
		ReadHeaderTimeout: timeout,
		IdleTimeout:       timeout,
	}), false)

	pr, pw := io.Pipe()
	go func() {
		for range 6 {
			time.Sleep(timeout)
			_, _ = pw.Write([]byte("chunk"))
		}
		_ = pw.Close()
	}()
	resp, err := http.Post("http://"+addr+"/", "application/octet-stream", pr)
	if err != nil {
		t.Fatalf("post: %v", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if len(body) != 30 {
		t.Errorf("server read %d body bytes; want 30 — the upload was cut off", len(body))
	}
}

// TestNewHTTPServer_OffersHTTP2OverTLS verifies ALPN settles on h2 for a client
// that offers it, and that HTTP/1.1 clients are still served.
func TestNewHTTPServer_OffersHTTP2OverTLS(t *testing.T) {
	addr := startServer(t, NewHTTPServer(NewHTTPServerParams{
		Handler:   okHandler(),
		TLSConfig: &tls.Config{Certificates: []tls.Certificate{testCert(t)}, MinVersion: tls.VersionTLS13},
	}), true)
	for _, proto := range []string{"h2", "http/1.1"} {
		t.Run(proto, func(t *testing.T) {
			conn, err := tls.Dial("tcp", addr, &tls.Config{
				InsecureSkipVerify: true, // the test's own self-signed cert
				NextProtos:         []string{proto},
			})
			if err != nil {
				t.Fatalf("dial: %v", err)
			}
			defer conn.Close()
			if got := conn.ConnectionState().NegotiatedProtocol; got != proto {
				t.Errorf("negotiated %q; want %q", got, proto)
			}
		})
	}
}
