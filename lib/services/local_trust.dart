/// Shared "may this unverifiable certificate be accepted?" policy.
///
/// A quark on the local network serves a self-signed certificate, so the
/// client must opt out of chain verification for it — and only for it. This is
/// the single source of truth for that decision; the HTTP client
/// ([buildLocalTrustHttpClient]), the app-wide `HttpOverrides`, the WebSocket
/// connector ([connectLocalTrustWs]) and the media proxy all call it so they
/// can never drift apart.
///
/// The policy (#2154): a public or tailnet name is never accepted. A client
/// built for the Quark the user chose accepts what [isLocalTrustHost] calls
/// local; any other client accepts a private, loopback or link-local address,
/// and a local name only when it is one the user chose
/// ([acceptsUnverifiedCertificate]) — a name that merely ends in `.local` or
/// `.lan` is not enough. This narrows who can present a forged certificate; it does
/// not stop a hostile network that answers for the user's own Quark name or
/// address, which only pinning the certificate would.
///
/// Deliberately pure Dart (no `dart:io`, no Flutter) so it can be imported from
/// web builds and unit-tested without a binding.
library;

/// Hostname suffixes that only ever resolve inside a local network.
///
/// `.local` is mDNS/Bonjour — the primary way the app reaches a quark
/// (`openclaw.local`, `quark.local`). The rest are the conventional
/// private-network suffixes; `.home.arpa` is the RFC 8375 standard one.
const _localSuffixes = <String>[
  '.local',
  '.lan',
  '.home',
  '.home.arpa',
  '.internal',
];

/// Returns true when [host] is reachable only from the local network and so is
/// expected to present a self-signed certificate: a [isPrivateAddress], a name
/// under a local suffix, or a single-label name.
///
/// This is the shape of a Quark's address, not permission to trust one — that
/// is [acceptsUnverifiedCertificate]. A client built for a host the user chose
/// checks it to decide whether to install a certificate callback at all.
///
/// Accepts hostnames and IPv4/IPv6 literals. [host] should be a bare host —
/// [Uri.host], not an authority — since ports and brackets are not stripped.
bool isLocalTrustHost(String? host) {
  if (host == null || host.isEmpty) return false;
  if (isPrivateAddress(host)) return true;

  final normalized = host.toLowerCase();
  if (normalized.contains(':')) return false;
  for (final suffix in _localSuffixes) {
    if (normalized.endsWith(suffix)) return true;
  }

  // A single-label name (no dot) can only be resolved by mDNS, NetBIOS, or a
  // local DNS search domain — never by public DNS.
  return !normalized.contains('.');
}

/// Returns true for `localhost` and for IPv4/IPv6 literals in the private,
/// loopback and link-local ranges.
///
/// The Android emulator's alias for the developer machine, `10.0.2.2`, falls
/// inside `10.0.0.0/8`.
bool isPrivateAddress(String? host) {
  if (host == null || host.isEmpty) return false;
  final normalized = host.toLowerCase();
  if (normalized == 'localhost') return true;
  if (normalized.contains(':')) return _isPrivateIpv6(normalized);
  return _isPrivateIpv4(normalized);
}

/// Whether a certificate that failed verification may be accepted from
/// [host], given the hosts the user chose in [chosenHosts].
///
/// This is the rule for clients the app does not point at a host itself —
/// `Image.network`, bare `http.get` — via `LocalTrustHttpOverrides`. [host] is
/// what the TLS layer reports for the connection; [chosenHosts] are bare hosts
/// ([Uri.host]) of the saved Quarks and the one in use. A private address is accepted whatever was chosen, since iOS can
/// report the mDNS-resolved address rather than the name that was dialed. A
/// local name must match a chosen host, so a redirect to, or an image from,
/// some other `.lan` box is verified as normal.
bool acceptsUnverifiedCertificate(String? host, Iterable<String?> chosenHosts) {
  if (host == null || host.isEmpty) return false;
  if (isPrivateAddress(host)) return true;
  if (!isLocalTrustHost(host)) return false;
  final normalized = host.toLowerCase();
  return chosenHosts.any((chosen) => chosen?.toLowerCase() == normalized);
}

/// Returns true for RFC 1918 private ranges, loopback, and link-local IPv4.
bool _isPrivateIpv4(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return false;

  final octets = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return false;
    octets.add(value);
  }

  final first = octets[0];
  final second = octets[1];

  if (first == 10) return true; // 10.0.0.0/8
  if (first == 127) return true; // 127.0.0.0/8 loopback
  // 172.16.0.0/12
  if (first == 172 && second >= 16 && second <= 31) return true;
  if (first == 192 && second == 168) return true; // 192.168.0.0/16
  if (first == 169 && second == 254) return true; // 169.254.0.0/16 link-local
  return false;
}

/// Returns true for IPv6 loopback, link-local (fe80::/10), and unique local
/// (fc00::/7) addresses.
bool _isPrivateIpv6(String host) {
  // Uri.host keeps the zone id on link-local literals (fe80::1%en0).
  final address = host.split('%').first;

  if (address == '::1') return true;
  if (address.startsWith('fe8') ||
      address.startsWith('fe9') ||
      address.startsWith('fea') ||
      address.startsWith('feb')) {
    return true; // fe80::/10
  }
  if (address.startsWith('fc') || address.startsWith('fd')) {
    return true; // fc00::/7
  }
  return false;
}
