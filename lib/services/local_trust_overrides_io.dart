// IO implementation: applies the local-trust policy to every HttpClient the
// app creates, including ones we don't construct ourselves.
import 'dart:io';

import 'package:quark/services/app_settings.dart';
import 'package:quark/services/local_trust.dart';

/// Applies [acceptsUnverifiedCertificate] to every [HttpClient] created in this
/// isolate.
///
/// [buildLocalTrustHttpClient] only covers services that go through the
/// [AuthenticatedService] mixin. Several services call the top-level
/// `http.get`/`http.post` helpers, and widgets like `Image.network` create
/// their own clients — all of which would otherwise reject the quark's
/// self-signed certificate. Installing an override catches them all in one
/// place.
///
/// The hosts these clients may reach are not chosen by the user, so a local
/// name is trusted only when it is one of the saved Quarks' addresses (home or
/// remote) or the address in use (#2154). Being connected to a local Quark
/// does not loosen verification for any other host.
class LocalTrustHttpOverrides extends HttpOverrides {
  /// [chosenAddresses] lists the addresses the user picked; it defaults to the
  /// saved Quarks plus [activeBaseUrl] and is read again on every handshake, so
  /// a Quark added later is trusted without reinstalling the override.
  LocalTrustHttpOverrides({List<String?> Function()? chosenAddresses})
    : _chosenAddresses = chosenAddresses ?? _savedAddresses;

  final List<String?> Function() _chosenAddresses;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => trusts(host);
  }

  /// Whether a certificate that failed verification is accepted from [host].
  bool trusts(String host) => acceptsUnverifiedCertificate(host, [
    for (final address in _chosenAddresses()) _hostOf(address),
  ]);

  static List<String?> _savedAddresses() => [
    activeBaseUrl,
    for (final entry in AppSettings.instance.hosts) ...[
      entry.hostAddress,
      entry.remoteAddress,
    ],
  ];

  static String? _hostOf(String? address) {
    if (address == null || address.isEmpty) return null;
    return Uri.tryParse(address)?.host;
  }
}

void installLocalTrustHttpOverrides() {
  HttpOverrides.global = LocalTrustHttpOverrides();
}
