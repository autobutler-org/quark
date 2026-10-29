package feedutil

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

func publicLookup(t *testing.T, host string) IPLookup {
	t.Helper()
	ip := net.ParseIP("203.0.113.5")
	return func(ctx context.Context, got string) ([]net.IP, error) {
		if got != host {
			return nil, errors.New("lookup " + got)
		}
		return []net.IP{ip}, nil
	}
}

func TestSafeFetchPinsTheAddressAndDropsTheReferer(t *testing.T) {
	var referer string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/start":
			http.Redirect(w, r, "http://feeds.example/next", http.StatusFound)
		default:
			referer = r.Referer()
			w.Header().Set("Content-Type", "text/html")
			_, _ = io.WriteString(w, `<link rel="alternate" type="application/rss+xml" title="T" href="/feed.xml">`+strings.Repeat(" ", 64))
		}
	}))
	t.Cleanup(srv.Close)

	var dialed []string
	fetcher := safeFetcher{
		lookup: publicLookup(t, "feeds.example"),
		dial: func(ctx context.Context, network, addr string) (net.Conn, error) {
			dialed = append(dialed, addr)
			if addr != "203.0.113.5:80" {
				return nil, errors.New("dialed " + addr)
			}
			return (&net.Dialer{}).DialContext(ctx, network, srv.Listener.Addr().String())
		},
	}
	pageURL, err := url.Parse("http://feeds.example/start?token=opaque-token")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	page, err := fetcher.Fetch(ctx, pageURL)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(referer, "opaque-token") {
		t.Fatalf("referer = %q", referer)
	}
	if len(dialed) == 0 || dialed[0] != "203.0.113.5:80" {
		t.Fatalf("dialed %v", dialed)
	}
	found := candidatesFromPage(page)
	if len(found.candidates) != 1 || found.candidates[0].URL != "http://feeds.example/feed.xml" {
		t.Fatalf("candidates = %+v", found.candidates)
	}
}

func TestSafeFetchRejectsAPrivateRedirect(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "http://127.0.0.1/admin?token=other-secret", http.StatusFound)
	}))
	t.Cleanup(srv.Close)
	fetcher := safeFetcher{
		lookup: publicLookup(t, "feeds.example"),
		dial: func(ctx context.Context, network, addr string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, network, srv.Listener.Addr().String())
		},
	}
	pageURL, err := url.Parse("http://feeds.example/start?token=opaque-token")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_, err = fetcher.Fetch(ctx, pageURL)
	if !errors.Is(err, ErrForbiddenAddress) || strings.Contains(err.Error(), "opaque-token") || strings.Contains(err.Error(), "other-secret") || strings.Contains(err.Error(), "127.0.0.1") {
		t.Fatalf("error = %v", err)
	}
}

func TestSafeFetchDoesNotDialAPrivateAnswer(t *testing.T) {
	fetcher := safeFetcher{
		lookup: func(context.Context, string) ([]net.IP, error) {
			return []net.IP{net.ParseIP("10.0.0.1")}, nil
		},
		dial: func(context.Context, string, string) (net.Conn, error) {
			t.Fatal("dialed a private address")
			return nil, errors.New("dialed")
		},
	}
	pageURL, err := url.Parse("http://feeds.example/feed?token=opaque-token")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_, err = fetcher.Fetch(ctx, pageURL)
	if !errors.Is(err, ErrForbiddenAddress) || strings.Contains(err.Error(), "opaque-token") {
		t.Fatalf("error = %v", err)
	}
}

func TestSafeFetchHidesATransportError(t *testing.T) {
	fetcher := safeFetcher{
		lookup: publicLookup(t, "feeds.example"),
		dial: func(context.Context, string, string) (net.Conn, error) {
			return nil, errors.New("connection refused")
		},
	}
	pageURL, err := url.Parse("http://feeds.example/feed?token=opaque-token")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_, err = fetcher.Fetch(ctx, pageURL)
	if !errors.Is(err, ErrFetchFailed) || strings.Contains(err.Error(), "opaque-token") || strings.Contains(err.Error(), "feeds.example") {
		t.Fatalf("error = %v", err)
	}
}

func TestSafeFetchCapsTheBody(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		_, _ = io.WriteString(w, `<link rel="alternate" type="application/atom+xml" href="/a.xml" title="A">`)
		_, _ = io.WriteString(w, strings.Repeat("x", maxPageBytes+4096))
	}))
	t.Cleanup(srv.Close)
	fetcher := safeFetcher{
		lookup: publicLookup(t, "feeds.example"),
		dial: func(ctx context.Context, network, addr string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, network, srv.Listener.Addr().String())
		},
	}
	pageURL, err := url.Parse("http://feeds.example/")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	page, err := fetcher.Fetch(ctx, pageURL)
	if err != nil {
		t.Fatal(err)
	}
	if int64(len(page.Body)) > maxPageBytes {
		t.Fatalf("body = %d bytes", len(page.Body))
	}
	found := candidatesFromPage(page)
	if len(found.candidates) != 1 || found.candidates[0].Title != "A" {
		t.Fatalf("candidates = %+v", found.candidates)
	}
}
