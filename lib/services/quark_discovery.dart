import 'package:quark/services/app_settings.dart';
import 'package:quark/services/quark_discovery_stub.dart'
    if (dart.library.io) 'package:quark/services/quark_discovery_io.dart'
    as platform;

/// Browses the local network for Quarks and emits every one found so far,
/// again each time one appears or goes away. Canceling the subscription stops
/// the browse.
typedef QuarkBrowser = Stream<List<HostEntry>> Function();

/// The DNS-SD service type a Quark image advertises (#2312).
const String quarkServiceType = '_quark._tcp';

/// The browser for this platform, or null where it cannot browse mDNS: the
/// web, whose browsers expose no mDNS, and desktop, which nobody has asked
/// for. Only iOS and Android browse.
QuarkBrowser? get quarkBrowser => platform.quarkBrowser;

/// The entry a resolved Quark service becomes, named [name] and addressed by
/// [host] and [port], or null when [host] is not usable in a URL.
///
/// [host] is whatever the platform resolved: the SRV target on iOS
/// (`quark-2.local.`), the IP address on Android.
HostEntry? discoveredQuark({
  required String name,
  required String? host,
  required int port,
}) {
  var h = host?.trim() ?? '';
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  // ponytail: a scoped IPv6 address (fe80::1%en0) is dropped rather than
  // escaped into a URL. Escape the zone as %25 if a Quark ever resolves only
  // to one.
  if (h.isEmpty || h.contains('%')) return null;
  if (h.contains(':')) h = '[$h]';
  final portSuffix = port == 443 || port <= 0 ? '' : ':$port';
  return HostEntry(name: name, hostAddress: 'https://$h$portSuffix');
}
