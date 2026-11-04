package main

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// TokenHeader carries the per-start token. The proxy answers 403 to a
// request without it and never forwards it to the Quark.
const TokenHeader = "X-Quark-Tunnel-Token"

// serveProxy listens on 127.0.0.1 and forwards each request to upstream over
// dial. Response bodies are streamed with io.Copy. Nothing is buffered.
//
// Any app on the phone, and any web page in its browser, can open a socket to
// 127.0.0.1. So the proxy only forwards a request that carries the token it
// returns, which is new on every start and handed to the app alone, and whose
// Host is exactly 127.0.0.1:<port>, which a page that points its own name at
// 127.0.0.1 cannot send.
func serveProxy(upstream string, dial DialFunc) (int, string, *http.Server, error) {
	if dial == nil {
		return 0, "", nil, errors.New("dial is nil")
	}
	target, err := parseUpstream(upstream)
	if err != nil {
		return 0, "", nil, err
	}
	secret := make([]byte, 32)
	if _, err := rand.Read(secret); err != nil {
		return 0, "", nil, err
	}
	token := hex.EncodeToString(secret)
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, "", nil, err
	}
	transport := &http.Transport{
		DialContext:         dial,
		DisableCompression:  true,
		MaxIdleConnsPerHost: 8,
		IdleConnTimeout:     90 * time.Second,
	}
	srv := &http.Server{
		Handler: &forwarder{
			target:    target,
			transport: transport,
			host:      ln.Addr().String(),
			token:     token,
		},
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       120 * time.Second,
	}
	go func() { _ = srv.Serve(ln) }()
	return ln.Addr().(*net.TCPAddr).Port, token, srv, nil
}

// forwarder is one upstream. An Upgrade, such as the events websocket, is
// copied in both directions. Every other response body is io.Copy'd to the
// client.
type forwarder struct {
	target    *url.URL
	transport *http.Transport
	// host is the only Host a request may name: 127.0.0.1:<port>.
	host  string
	token string
}

func (p *forwarder) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// 403 rather than 401: the app reads a 401 as an expired Quark session.
	if r.Host != p.host || subtle.ConstantTimeCompare([]byte(r.Header.Get(TokenHeader)), []byte(p.token)) != 1 {
		w.WriteHeader(http.StatusForbidden)
		return
	}
	// Transport reads Request.Body on its own goroutine while the response
	// is copied below. Full duplex keeps that read alive across Write so
	// a large response is not cut off.
	if err := http.NewResponseController(w).EnableFullDuplex(); err != nil {
		w.WriteHeader(http.StatusBadGateway)
		return
	}

	upgrade := isUpgrade(r.Header)
	out := *p.target
	out.Path = r.URL.Path
	out.RawPath = r.URL.RawPath
	out.RawQuery = r.URL.RawQuery
	req, err := http.NewRequestWithContext(r.Context(), r.Method, out.String(), r.Body)
	if err != nil {
		w.WriteHeader(http.StatusBadGateway)
		return
	}
	copyHeader(req.Header, r.Header, upgrade)
	req.Header.Del(TokenHeader)
	req.ContentLength = r.ContentLength
	resp, err := p.transport.RoundTrip(req)
	if err != nil {
		w.WriteHeader(http.StatusBadGateway)
		return
	}
	if resp.StatusCode == http.StatusSwitchingProtocols {
		switchProtocol(w, resp)
		return
	}
	defer resp.Body.Close()
	copyHeader(w.Header(), resp.Header, false)
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(flushOnWrite{ResponseWriter: w}, resp.Body)
}

// flushOnWrite flushes after each chunk so an event stream and a media
// download move as bytes arrive, instead of collecting the body first.
type flushOnWrite struct{ http.ResponseWriter }

func (f flushOnWrite) Write(p []byte) (int, error) {
	n, err := f.ResponseWriter.Write(p)
	if fl, ok := f.ResponseWriter.(http.Flusher); ok {
		fl.Flush()
	}
	return n, err
}

func switchProtocol(w http.ResponseWriter, resp *http.Response) {
	back, ok := resp.Body.(io.ReadWriteCloser)
	if !ok {
		_ = resp.Body.Close()
		w.WriteHeader(http.StatusBadGateway)
		return
	}
	conn, brw, err := http.NewResponseController(w).Hijack()
	if err != nil {
		_ = back.Close()
		w.WriteHeader(http.StatusBadGateway)
		return
	}
	copyHeader(w.Header(), resp.Header, true)
	resp.Header = w.Header()
	resp.Body = nil
	if err := resp.Write(brw); err != nil {
		_ = conn.Close()
		_ = back.Close()
		return
	}
	if err := brw.Flush(); err != nil {
		_ = conn.Close()
		_ = back.Close()
		return
	}
	var once sync.Once
	closeBoth := func() {
		once.Do(func() {
			_ = conn.Close()
			_ = back.Close()
		})
	}
	go func() {
		_, _ = io.Copy(conn, back)
		closeBoth()
	}()
	go func() {
		_, _ = io.Copy(back, conn)
		closeBoth()
	}()
}

func isUpgrade(h http.Header) bool {
	for _, v := range h["Connection"] {
		for _, part := range strings.Split(v, ",") {
			if strings.EqualFold(strings.TrimSpace(part), "upgrade") {
				return true
			}
		}
	}
	return false
}

// hopByHop are the headers RFC 7230 says a proxy does not forward.
var hopByHop = map[string]bool{
	"Connection":          true,
	"Proxy-Connection":    true,
	"Keep-Alive":          true,
	"Proxy-Authenticate":  true,
	"Proxy-Authorization": true,
	"Te":                  true,
	"Trailer":             true,
	"Transfer-Encoding":   true,
	"Upgrade":             true,
}

func copyHeader(dst, src http.Header, keepUpgrade bool) {
	named := map[string]bool{}
	for _, v := range src["Connection"] {
		for _, part := range strings.Split(v, ",") {
			if part = strings.TrimSpace(part); part != "" {
				named[http.CanonicalHeaderKey(part)] = true
			}
		}
	}
	for k, vs := range src {
		keep := keepUpgrade && (k == "Connection" || k == "Upgrade")
		if hopByHop[k] && !keep {
			continue
		}
		if named[k] && !keep {
			continue
		}
		for _, v := range vs {
			dst.Add(k, v)
		}
	}
}

func parseUpstream(s string) (*url.URL, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil, errors.New("upstream is empty")
	}
	if !strings.Contains(s, "://") {
		s = "http://" + s
	}
	u, err := url.Parse(s)
	if err != nil || u.Host == "" {
		return nil, errors.New("upstream is not an address like http://100.64.0.1")
	}
	if u.Scheme != "http" {
		return nil, errors.New("upstream scheme is not supported; the Quark serves plain HTTP on the tailnet")
	}
	if u.Port() == "" {
		u.Host = net.JoinHostPort(u.Hostname(), "80")
	}
	return &url.URL{Scheme: u.Scheme, Host: u.Host}, nil
}
