package remoteutil

import (
	"net/http"
	"net/url"
	"testing"
)

// TestNewProxy_KeepsEnoughIdleConnections verifies the proxy keeps more than
// the default two idle loopback connections, so a remote client with several
// requests in flight does not make it open a fresh TLS connection, a full
// handshake each, for every one past the second (#2755).
func TestNewProxy_KeepsEnoughIdleConnections(t *testing.T) {
	target := &url.URL{Scheme: "https", Host: "localhost:443"}
	for _, localTLS := range []bool{true, false} {
		transport, ok := newProxy(target, localTLS).Transport.(*http.Transport)
		if !ok {
			t.Fatalf("localTLS=%v: Transport is %T; want *http.Transport", localTLS, newProxy(target, localTLS).Transport)
		}
		if transport.MaxIdleConnsPerHost < proxyMaxIdleConnsPerHost {
			t.Errorf("localTLS=%v: MaxIdleConnsPerHost = %d; want at least %d",
				localTLS, transport.MaxIdleConnsPerHost, proxyMaxIdleConnsPerHost)
		}
		if localTLS && (transport.TLSClientConfig == nil || !transport.TLSClientConfig.InsecureSkipVerify) {
			t.Errorf("localTLS: TLSClientConfig = %+v; want the loopback hop to accept the self-signed cert",
				transport.TLSClientConfig)
		}
	}
}
