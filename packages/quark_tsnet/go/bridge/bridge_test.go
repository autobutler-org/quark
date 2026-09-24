package bridge

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"tailscale.com/net/netns"
	"tailscale.com/tailcfg"
	"tailscale.com/tsnet"
	"tailscale.com/tstest/integration"
	"tailscale.com/tstest/integration/testcontrol"
	"tailscale.com/types/logger"
)

// TestProxyRoundTrip runs the whole path with no network beyond loopback:
// tailscale's in-process control server and DERP, a tsnet node playing the
// Quark, and the bridge as the phone. A GET and a Range GET go through the
// loopback proxy and must come back intact.
func TestProxyRoundTrip(t *testing.T) {
	// Same as tsnet's own tests: no socket marking on a dev machine.
	netns.SetEnabled(false)
	t.Cleanup(func() { netns.SetEnabled(true) })

	derpMap := integration.RunDERPAndSTUN(t, logger.Discard, "127.0.0.1")
	control := &testcontrol.Server{DERPMap: derpMap, DNSConfig: &tailcfg.DNSConfig{Proxied: true}}
	control.HTTPTestServer = httptest.NewUnstartedServer(control)
	control.HTTPTestServer.Start()
	t.Cleanup(control.HTTPTestServer.Close)
	controlURL := control.HTTPTestServer.URL

	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	// The fake Quark. Unlike a phone, a Quark does listen on the tailnet.
	body := bytes.Repeat([]byte("0123456789"), 100_000) // 1 MB
	quark := &tsnet.Server{Dir: t.TempDir(), ControlURL: controlURL, Hostname: "quark", Logf: logger.Discard}
	t.Cleanup(func() { _ = quark.Close() })
	st, err := quark.Up(ctx)
	if err != nil {
		t.Fatalf("quark up: %v", err)
	}
	ln, err := quark.Listen("tcp", ":80")
	if err != nil {
		t.Fatalf("quark listen: %v", err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/api/v0/version", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, `{"version":"test"}`)
	})
	mux.HandleFunc("/video.mp4", func(w http.ResponseWriter, r *http.Request) {
		http.ServeContent(w, r, "video.mp4", time.Time{}, bytes.NewReader(body))
	})
	go func() { _ = http.Serve(ln, mux) }()

	port, err := Start(Config{
		StateDir:   t.TempDir(),
		ControlURL: controlURL,
		AuthKey:    "testcontrol-accepts-any-key",
		Hostname:   "phone",
		Upstream:   fmt.Sprintf("http://%s", st.TailscaleIPs[0]),
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { _ = Stop() })
	if s := CurrentStatus(); s.State != "Running" || len(s.TailnetIPs) == 0 || s.Port != port {
		t.Fatalf("status after start = %+v", s)
	}
	if corpDNS(ctx, t) {
		t.Fatal("tailnet DNS is on; want it off like --accept-dns=false")
	}
	base := fmt.Sprintf("http://127.0.0.1:%d", port)

	// The first dial can race the DERP handshake, so retry briefly.
	var got string
	for {
		resp, err := http.Get(base + "/api/v0/version")
		if err == nil {
			b, _ := io.ReadAll(resp.Body)
			_ = resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				got = string(b)
				break
			}
		}
		if ctx.Err() != nil {
			t.Fatalf("GET never succeeded: %v", err)
		}
		time.Sleep(200 * time.Millisecond)
	}
	if got != `{"version":"test"}` {
		t.Fatalf("GET body = %q", got)
	}

	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, base+"/video.mp4", nil)
	req.Header.Set("Range", "bytes=500000-500009")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("range GET: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()
	b, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusPartialContent {
		t.Fatalf("range status = %d, want 206", resp.StatusCode)
	}
	if want := "bytes 500000-500009/1000000"; resp.Header.Get("Content-Range") != want {
		t.Fatalf("Content-Range = %q, want %q", resp.Header.Get("Content-Range"), want)
	}
	if string(b) != "0123456789" {
		t.Fatalf("range body = %q", b)
	}

	if err := Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}
	if s := CurrentStatus(); s.State != "Stopped" || s.Port != 0 {
		t.Fatalf("status after stop = %+v", s)
	}
}

// corpDNS reports whether the bridge's node accepts tailnet DNS.
func corpDNS(ctx context.Context, t *testing.T) bool {
	t.Helper()
	mu.Lock()
	srv := node
	mu.Unlock()
	lc, err := srv.LocalClient()
	if err != nil {
		t.Fatal(err)
	}
	p, err := lc.GetPrefs(ctx)
	if err != nil {
		t.Fatal(err)
	}
	return p.CorpDNS
}

func TestParseUpstream(t *testing.T) {
	for in, want := range map[string]string{
		"http://100.64.0.1":    "http://100.64.0.1:80",
		"http://100.64.0.1:80": "http://100.64.0.1:80",
		"100.64.0.1":           "http://100.64.0.1:80",
		" 100.64.0.1:8080 ":    "http://100.64.0.1:8080",
		"http://100.64.0.1/x":  "http://100.64.0.1:80",
	} {
		u, err := parseUpstream(in)
		if err != nil || u.String() != want {
			t.Errorf("parseUpstream(%q) = %v, %v; want %s", in, u, err, want)
		}
	}
	for _, in := range []string{"", "https://100.64.0.1", "http://"} {
		if _, err := parseUpstream(in); err == nil {
			t.Errorf("parseUpstream(%q) succeeded; want an error", in)
		}
	}
}
