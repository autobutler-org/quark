package serverutil

import (
	"strings"
	"testing"
)

func trustedProxyStrings(t *testing.T) []string {
	t.Helper()
	nets, err := TrustedProxies()
	if err != nil {
		t.Fatalf("TrustedProxies() error = %v", err)
	}
	out := make([]string, 0, len(nets))
	for _, n := range nets {
		out = append(out, n.String())
	}
	return out
}

func TestTrustedProxies_DefaultIsLoopback(t *testing.T) {
	t.Setenv("QUARK_TRUSTED_PROXIES", "")
	got := strings.Join(trustedProxyStrings(t), ",")
	if want := "127.0.0.1/32,::1/128"; got != want {
		t.Errorf("TrustedProxies() = %s; want %s", got, want)
	}
}

func TestTrustedProxies_EnvReplacesDefault(t *testing.T) {
	t.Setenv("QUARK_TRUSTED_PROXIES", " 10.0.0.0/8, 192.168.1.5 ,fd00::/8,")
	got := strings.Join(trustedProxyStrings(t), ",")
	if want := "10.0.0.0/8,192.168.1.5/32,fd00::/8"; got != want {
		t.Errorf("TrustedProxies() = %s; want %s", got, want)
	}
}

func TestTrustedProxies_InvalidEntryNamesVariableAndEntry(t *testing.T) {
	t.Setenv("QUARK_TRUSTED_PROXIES", "10.0.0.0/8,not-an-ip")
	_, err := TrustedProxies()
	if err == nil {
		t.Fatal("TrustedProxies() accepted not-an-ip")
	}
	for _, want := range []string{"QUARK_TRUSTED_PROXIES", `"not-an-ip"`} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error %q does not mention %s", err, want)
		}
	}
}

func TestIsTrustedProxy(t *testing.T) {
	t.Setenv("QUARK_TRUSTED_PROXIES", "10.0.0.0/8,::1")
	cases := map[string]bool{
		"10.1.2.3":    true,
		"::1":         true,
		"127.0.0.1":   false,
		"203.0.113.7": false,
		"":            false,
		"garbage":     false,
	}
	for ip, want := range cases {
		if got := IsTrustedProxy(ip); got != want {
			t.Errorf("IsTrustedProxy(%q) = %v; want %v", ip, got, want)
		}
	}
}
