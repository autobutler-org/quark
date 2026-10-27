package main

import (
	"bytes"
	"context"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"tailscale.com/envknob"
)

func TestStartStopStatus_ProxiesThroughInjectedDial(t *testing.T) {
	const upstream = "http://100.64.0.1"
	body := bytes.Repeat([]byte("abc"), 350000)
	var dialed string
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v0/version" || r.URL.RawQuery != "q=1" {
			t.Errorf("url = %s?%s", r.URL.Path, r.URL.RawQuery)
		}
		if r.Header.Get("Range") != "bytes=0-4" {
			t.Errorf("Range = %q", r.Header.Get("Range"))
		}
		if r.Header.Get(TokenHeader) != "" {
			t.Error("the token reached the Quark")
		}
		if r.Host != "100.64.0.1:80" {
			t.Errorf("Host = %q", r.Host)
		}
		got, err := io.ReadAll(r.Body)
		if err != nil {
			t.Errorf("read body: %v", err)
		}
		if !bytes.Equal(got, []byte("ping")) {
			t.Errorf("body = %q", got)
		}
		w.Header().Set("Content-Range", "bytes 0-4/10")
		w.WriteHeader(http.StatusPartialContent)
		if _, err := w.Write(body); err != nil {
			t.Errorf("write: %v", err)
		}
	}))
	t.Cleanup(backend.Close)

	if st := Status(); st.State != "Stopped" || st.Port != 0 || st.Error != "" {
		t.Fatalf("initial status = %+v", st)
	}

	port, token, err := Start(Config{
		Upstream: upstream,
		Dial: func(_ context.Context, network, addr string) (net.Conn, error) {
			if network != "tcp" {
				t.Errorf("network = %s", network)
			}
			dialed = addr
			return net.Dial("tcp", backend.Listener.Addr().String())
		},
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { _ = Stop() })
	if dialed != "" {
		t.Fatal("dial ran before a request")
	}

	st := Status()
	if st.State != "Running" || st.Port != port || st.Error != "" || len(st.TailnetIPs) != 0 {
		t.Fatalf("running status = %+v, port %d", st, port)
	}
	if _, _, err := Start(Config{Upstream: upstream, Dial: func(context.Context, string, string) (net.Conn, error) {
		t.Fatal("second start dialed")
		return nil, nil
	}}); err == nil || !strings.Contains(err.Error(), "already running") {
		t.Fatalf("second Start err = %v", err)
	}

	// The server closes a request body when the handler writes the response.
	// Repeating the exchange makes that race fail the test instead of slipping
	// through one lucky run.
	for try := 0; try < 24; try++ {
		req, err := http.NewRequest(http.MethodPost, "http://127.0.0.1:"+strconv.Itoa(port)+"/api/v0/version?q=1", strings.NewReader("ping"))
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Range", "bytes=0-4")
		req.Header.Set(TokenHeader, token)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		if resp.StatusCode != http.StatusPartialContent {
			resp.Body.Close()
			t.Fatalf("try %d: status = %d", try, resp.StatusCode)
		}
		if resp.Header.Get("Content-Range") != "bytes 0-4/10" {
			resp.Body.Close()
			t.Fatalf("try %d: Content-Range = %q", try, resp.Header.Get("Content-Range"))
		}
		got, err := io.ReadAll(resp.Body)
		resp.Body.Close()
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(got, body) {
			t.Fatalf("try %d: response length = %d, want %d", try, len(got), len(body))
		}
	}
	if dialed != "100.64.0.1:80" {
		t.Fatalf("dialed %q", dialed)
	}

	if err := Stop(); err != nil {
		t.Fatal(err)
	}
	st = Status()
	if st.State != "Stopped" || st.Port != 0 {
		t.Fatalf("stopped status = %+v", st)
	}
	if err := Stop(); err != nil {
		t.Fatalf("second Stop: %v", err)
	}
}

func TestStart_RejectsBadUpstream(t *testing.T) {
	dial := func(context.Context, string, string) (net.Conn, error) {
		t.Fatal("dialed")
		return nil, nil
	}
	if _, _, err := Start(Config{Dial: dial}); err == nil {
		t.Fatal("empty upstream started")
	}
	st := Status()
	if st.State != "Stopped" || st.Port != 0 || st.Error == "" {
		t.Fatalf("status after failure = %+v", st)
	}
	// A rejected start must not stick the bridge in the running state.
	if _, _, err := Start(Config{Upstream: "https://100.64.0.1", Dial: dial}); err == nil {
		t.Fatal("https upstream started")
	}
}

func TestParseUpstream(t *testing.T) {
	cases := []struct {
		in   string
		host string
		err  bool
	}{
		{in: "http://100.64.0.1", host: "100.64.0.1:80"},
		{in: "http://100.64.0.1:8080", host: "100.64.0.1:8080"},
		{in: "  100.64.0.1 ", host: "100.64.0.1:80"},
		{in: "", err: true},
		{in: "https://100.64.0.1", err: true},
		{in: "not a url", err: true},
	}
	for _, tc := range cases {
		u, err := parseUpstream(tc.in)
		if tc.err {
			if err == nil {
				t.Errorf("parseUpstream(%q) = %v, want error", tc.in, u)
			}
			continue
		}
		if err != nil {
			t.Errorf("parseUpstream(%q): %v", tc.in, err)
			continue
		}
		if u.Scheme != "http" || u.Host != tc.host || u.Path != "" {
			t.Errorf("parseUpstream(%q) = %s %s", tc.in, u.Scheme, u.Host)
		}
	}
}

func TestProxy_ForwardsUpgrade(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hj, ok := w.(http.Hijacker)
		if !ok {
			t.Fatal("no hijack")
		}
		conn, buf, err := hj.Hijack()
		if err != nil {
			t.Fatal(err)
		}
		defer conn.Close()
		if _, err := buf.WriteString("HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n"); err != nil {
			t.Fatal(err)
		}
		if err := buf.Flush(); err != nil {
			t.Fatal(err)
		}
		got := make([]byte, 4)
		if _, err := io.ReadFull(buf, got); err != nil {
			t.Fatal(err)
		}
		if string(got) != "ping" {
			t.Fatalf("upgrade payload = %q", got)
		}
		if _, err := buf.WriteString("pong"); err != nil {
			t.Fatal(err)
		}
		if err := buf.Flush(); err != nil {
			t.Fatal(err)
		}
	}))
	t.Cleanup(backend.Close)

	port, token, err := Start(Config{
		Upstream: "http://100.64.0.2",
		Dial: func(context.Context, string, string) (net.Conn, error) {
			return net.Dial("tcp", backend.Listener.Addr().String())
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = Stop() })

	req, err := http.NewRequest(http.MethodGet, "http://127.0.0.1:"+strconv.Itoa(port)+"/api/v0/events", nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Connection", "Upgrade")
	req.Header.Set("Upgrade", "websocket")
	req.Header.Set(TokenHeader, token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusSwitchingProtocols {
		t.Fatalf("status = %d", resp.StatusCode)
	}
	rw, ok := resp.Body.(io.ReadWriter)
	if !ok {
		t.Fatalf("body type %T", resp.Body)
	}
	if _, err := rw.Write([]byte("ping")); err != nil {
		t.Fatal(err)
	}
	got := make([]byte, 4)
	if _, err := io.ReadFull(rw, got); err != nil {
		t.Fatal(err)
	}
	if string(got) != "pong" {
		t.Fatalf("pong = %q", got)
	}
}

func TestProxy_RejectsMissingTokenWrongTokenAndForeignHost(t *testing.T) {
	dialed := 0
	noDial := func(context.Context, string, string) (net.Conn, error) {
		dialed++
		return nil, io.EOF
	}
	port, token, err := Start(Config{Upstream: "http://100.64.0.3", Dial: noDial})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = Stop() })
	if len(token) != 64 || Token() != token {
		t.Fatalf("token = %q, Token() = %q", token, Token())
	}

	addr := "127.0.0.1:" + strconv.Itoa(port)
	cases := []struct {
		name, host, token string
	}{
		{name: "missing token", host: addr},
		{name: "wrong token", host: addr, token: strings.Repeat("0", 64)},
		{name: "foreign host", host: "rebind.example:" + strconv.Itoa(port), token: token},
		{name: "localhost", host: "localhost:" + strconv.Itoa(port), token: token},
		{name: "no port", host: "127.0.0.1", token: token},
	}
	for _, tc := range cases {
		req, err := http.NewRequest(http.MethodGet, "http://"+addr+"/api/v0/version", nil)
		if err != nil {
			t.Fatal(err)
		}
		req.Host = tc.host
		if tc.token != "" {
			req.Header.Set(TokenHeader, tc.token)
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatalf("%s: %v", tc.name, err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusForbidden {
			t.Errorf("%s: status = %d, want 403", tc.name, resp.StatusCode)
		}
	}
	if dialed != 0 {
		t.Fatalf("a rejected request dialed the Quark %d times", dialed)
	}

	if err := Stop(); err != nil {
		t.Fatal(err)
	}
	if Token() != "" {
		t.Fatal("the token outlived the proxy")
	}
	if _, next, err := Start(Config{Upstream: "http://100.64.0.3", Dial: noDial}); err != nil || next == token {
		t.Fatalf("restart: token reused %v, err %v", next == token, err)
	}
}

// TestUpNode_DisablesLogUploadBeforeNode verifies upNode turns off the
// networking library's diagnostic log upload before it builds a node, so a
// phone sends nothing to the library vendor (#3786). The config is rejected,
// so the node is never built and the switch must already be set.
func TestUpNode_DisablesLogUploadBeforeNode(t *testing.T) {
	envknob.SetenvForTest(t, "TS_NO_LOGS_NO_SUPPORT", "")
	if _, _, err := upNode(Config{}); err == nil {
		t.Fatal("upNode(Config{}) = nil error; want the missing-field error")
	}
	if !envknob.NoLogsNoSupport() {
		t.Fatal("NoLogsNoSupport() = false after upNode; want log upload off before the node is built")
	}
}
