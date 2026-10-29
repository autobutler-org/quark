package feedutil

import (
	"context"
	"net"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// checkAddress accepts an http or https URL whose host resolves only to
// public addresses. The returned URL is what gets stored: lowercase host,
// default port removed, fragment removed, token kept. Its error never
// contains raw.
func checkAddress(ctx context.Context, raw string, lookup IPLookup) (*url.URL, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" || len(raw) > maxURLLength || strings.ContainsAny(raw, " \t\r\n\\") {
		return nil, ErrInvalidURL
	}
	parsed, err := url.Parse(raw)
	if err != nil || parsed.Hostname() == "" || parsed.Opaque != "" {
		return nil, ErrInvalidURL
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return nil, ErrInvalidURL
	}
	if port := parsed.Port(); port != "" {
		n, conv := strconv.Atoi(port)
		if conv != nil || n < 1 || n > 65535 {
			return nil, ErrInvalidURL
		}
	}
	host := parsed.Hostname()
	if ip := net.ParseIP(host); ip != nil {
		if blockedIP(ip) {
			return nil, ErrForbiddenAddress
		}
	} else if err := rejectHost(ctx, host, lookup); err != nil {
		return nil, err
	}
	return canonical(parsed), nil
}

func rejectHost(ctx context.Context, host string, lookup IPLookup) error {
	if lookup == nil {
		lookup = defaultLookup
	}
	ips, err := lookup(ctx, host)
	if err != nil || len(ips) == 0 {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		return ErrUnresolved
	}
	good := 0
	for _, ip := range ips {
		if ip == nil {
			continue
		}
		if blockedIP(ip) {
			return ErrForbiddenAddress
		}
		good++
	}
	if good == 0 {
		return ErrUnresolved
	}
	return nil
}

// blockedIP reports addresses the box must not fetch. A home Quark can reach
// the LAN, the host itself, and the carrier range a home router sits behind.
func blockedIP(ip net.IP) bool {
	if ip == nil {
		return true
	}
	if v4 := ip.To4(); v4 != nil {
		ip = v4
	}
	if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() || ip.IsUnspecified() || ip.IsMulticast() {
		return true
	}
	v4 := ip.To4()
	if v4 == nil {
		return false
	}
	// 0.0.0.0/8 connects to this host on Linux. 100.64.0.0/10 is carrier-grade
	// NAT, which is not a public feed and is reachable from a home router.
	if v4[0] == 0 {
		return true
	}
	return v4[0] == 100 && v4[1]&0xc0 == 64
}

func canonical(u *url.URL) *url.URL {
	out := *u
	host := strings.ToLower(out.Hostname())
	port := out.Port()
	if (out.Scheme == "http" && port == "80") || (out.Scheme == "https" && port == "443") {
		port = ""
	}
	switch {
	case port == "" && strings.Contains(host, ":"):
		out.Host = "[" + host + "]"
	case port == "":
		out.Host = host
	default:
		out.Host = net.JoinHostPort(host, port)
	}
	out.Fragment = ""
	out.RawFragment = ""
	return &out
}

func defaultLookup(ctx context.Context, host string) ([]net.IP, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	addrs, err := net.DefaultResolver.LookupIPAddr(ctx, host)
	if err != nil {
		return nil, err
	}
	ips := make([]net.IP, 0, len(addrs))
	for _, addr := range addrs {
		if addr.IP != nil {
			ips = append(ips, addr.IP)
		}
	}
	return ips, nil
}
