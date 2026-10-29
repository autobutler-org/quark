package feedutil

import (
	"context"
	"crypto/tls"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"time"
)

// errTooManyRedirects stops a redirect chain. It is not returned to a caller.
var errTooManyRedirects = errors.New("too many redirects")

// safeFetcher fetches a public page. It dials an address it has already
// checked, so a name that starts public and then answers from the LAN is
// still refused. Redirects are checked the same way, and the Referer header
// is removed so a token in the first URL is not sent to the next host.
type safeFetcher struct {
	lookup IPLookup
	// dial, when set, connects to the pinned address. Nil uses net.Dialer.
	// Tests set it. The address is the resolved public IP, not the name.
	dial func(ctx context.Context, network, addr string) (net.Conn, error)
}

func (f safeFetcher) Fetch(ctx context.Context, page *url.URL) (pageBody, error) {
	checked, err := checkAddress(ctx, page.String(), f.lookup)
	if err != nil {
		return pageBody{}, err
	}
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()

	transport := &http.Transport{
		Proxy:                 nil,
		DialContext:           f.dialChecked,
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: 10 * time.Second,
		DisableKeepAlives:     true,
		// A compressed body can expand without bound. Ask for identity.
		DisableCompression:     true,
		MaxResponseHeaderBytes: 1 << 20,
		TLSNextProto:           map[string]func(string, *tls.Conn) http.RoundTripper{},
	}
	client := &http.Client{
		Transport: transport,
		Timeout:   15 * time.Second,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= maxRedirects {
				return errTooManyRedirects
			}
			if _, err := checkAddress(req.Context(), req.URL.String(), f.lookup); err != nil {
				return err
			}
			req.Header.Del("Referer")
			return nil
		},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, checked.String(), nil)
	if err != nil {
		return pageBody{}, ErrInvalidURL
	}
	req.Header.Set("User-Agent", "Quark")
	req.Header.Set("Accept", "text/html, application/xhtml+xml, application/rss+xml, application/atom+xml, */*")

	resp, err := client.Do(req)
	if resp != nil && resp.Body != nil {
		defer resp.Body.Close()
	}
	if err != nil {
		return pageBody{}, scrubFetch(err)
	}
	if resp.StatusCode != http.StatusOK {
		return pageBody{}, ErrFetchFailed
	}
	// The cap is ours, not the server's. Link tags sit in the head, and a
	// page past the cap is parsed from what was kept.
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxPageBytes+1))
	if err != nil {
		return pageBody{}, ErrFetchFailed
	}
	if int64(len(body)) > maxPageBytes {
		body = body[:maxPageBytes]
	}
	final := resp.Request.URL
	if final == nil {
		final = checked
	}
	canon, err := checkAddress(ctx, final.String(), f.lookup)
	if err != nil {
		return pageBody{}, err
	}
	return pageBody{URL: canon, ContentType: resp.Header.Get("Content-Type"), Body: body}, nil
}

func (f safeFetcher) dialChecked(ctx context.Context, network, addr string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return nil, ErrForbiddenAddress
	}
	ips, err := f.resolve(ctx, host)
	if err != nil {
		return nil, err
	}
	target := net.JoinHostPort(ips[0].String(), port)
	if f.dial != nil {
		return f.dial(ctx, network, target)
	}
	return (&net.Dialer{Timeout: 5 * time.Second}).DialContext(ctx, network, target)
}

func (f safeFetcher) resolve(ctx context.Context, host string) ([]net.IP, error) {
	if ip := net.ParseIP(host); ip != nil {
		if blockedIP(ip) {
			return nil, ErrForbiddenAddress
		}
		return []net.IP{ip}, nil
	}
	lookup := f.lookup
	if lookup == nil {
		lookup = defaultLookup
	}
	ips, err := lookup(ctx, host)
	if err != nil || len(ips) == 0 {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, ErrUnresolved
	}
	var good []net.IP
	for _, ip := range ips {
		if ip == nil {
			continue
		}
		if blockedIP(ip) {
			return nil, ErrForbiddenAddress
		}
		good = append(good, ip)
	}
	if len(good) == 0 {
		return nil, ErrUnresolved
	}
	return good, nil
}
