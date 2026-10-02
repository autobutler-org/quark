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

/// Suffixes a home network puts on a local name: mDNS's `.local`, and the
/// ones routers register DHCP clients under in their own DNS (#2518).
const _localNameSuffixes = ['.local', '.lan', '.home', '.localdomain'];

/// The other names a Quark typed as [address] may answer on (#2518), most
/// likely first, without [address] itself.
///
/// The Quark announces itself over mDNS as `quark.local`. Many routers also
/// register it in their own DNS as `quark.lan`, and a phone may resolve only
/// one of the two: Android before 12 cannot resolve `.local`, and a bare
/// `quark` resolves only where the router hands out a `lan` search domain.
/// Some routers even stack `.lan` onto the mDNS name, `quark.local.lan`.
///
/// So a name with a local suffix, or none, is stripped to its base and offered
/// as `<base>.local`, `<base>.lan` and the bare `<base>`. An IP address or a
/// public name has no variants, nor does `localhost`: each means exactly
/// what was typed.
List<String> localNameVariants(String address) {
  final uri = Uri.tryParse(address);
  final host = uri?.host ?? '';
  if (uri == null || host.isEmpty || host == 'localhost') return const [];
  if (host.contains(':')) return const [];
  if (RegExp(r'^\d+(\.\d+){3}$').hasMatch(host)) return const [];

  var base = host;
  for (var stripped = true; stripped;) {
    stripped = false;
    for (final suffix in _localNameSuffixes) {
      if (base.length > suffix.length && base.endsWith(suffix)) {
        base = base.substring(0, base.length - suffix.length);
        stripped = true;
      }
    }
  }
  if (base == host && host.contains('.')) return const [];

  final variants = <String>{'$base.local', '$base.lan', base}..remove(host);
  return [for (final h in variants) uri.replace(host: h).toString()];
}

/// The address a Quark typed as [address] answers on, or null when none does.
///
/// [address] is asked first and alone, so a name that works costs one probe.
/// Only when it does not answer are its [localNameVariants] asked, together,
/// and the first of them in that order that answered wins.
Future<String?> firstReachableAddress(
  String address,
  Future<bool> Function(String address) probe,
) async {
  if (await probe(address)) return address;
  final variants = localNameVariants(address);
  final answers = await Future.wait(variants.map(probe));
  for (var i = 0; i < variants.length; i++) {
    if (answers[i]) return variants[i];
  }
  return null;
}
