/// Shared "is this host on my own network?" predicate.
///
/// A quark on the local network serves a self-signed certificate, so the
/// client must opt out of chain verification for those hosts — and only those.
/// This is the single source of truth for that decision; both the HTTP client
/// ([buildLocalTrustHttpClient]) and the WebSocket connector
/// ([connectLocalTrustWs]) call it so the two can never drift apart.
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
/// expected to present a self-signed certificate.
///
/// Accepts hostnames and IPv4/IPv6 literals. [host] should be a bare host —
/// [Uri.host], not an authority — since ports and brackets are not stripped.
bool isLocalTrustHost(String? host) {
  if (host == null || host.isEmpty) return false;

  final normalized = host.toLowerCase();

  // Android emulator's alias for the developer machine's loopback.
  if (normalized == '10.0.2.2') return true;

  if (normalized == 'localhost') return true;
  for (final suffix in _localSuffixes) {
    if (normalized.endsWith(suffix)) return true;
  }

  // A single-label name (no dot) can only be resolved by mDNS, NetBIOS, or a
  // local DNS search domain — never by public DNS.
  if (!normalized.contains('.') && !normalized.contains(':')) return true;

  if (normalized.contains(':')) return _isPrivateIpv6(normalized);
  return _isPrivateIpv4(normalized);
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
