import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/local_trust.dart';
import 'package:quark/services/local_trust_pin_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secure_storage.dart';

/// A certificate that is nothing but its DER bytes, which is all pinning
/// reads.
class _FakeCertificate implements X509Certificate {
  _FakeCertificate(String content)
    : der = Uint8List.fromList(utf8.encode(content));

  @override
  final Uint8List der;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// #2721: the certificate callbacks pin a saved Quark's certificate by the
/// SHA-256 of its DER encoding.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const home = 'https://home.local';

  setUpAll(mockSecureStorage);

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'Home', 'hostAddress': home},
      ]),
    });
    await AppSettings.instance.load();
  });

  group('checkCertificatePin', () {
    test('nothing pinned is a first use', () {
      expect(
        checkCertificatePin(pinned: null, presented: 'aa'),
        CertificatePinCheck.firstUse,
      );
    });

    test('the pinned certificate matches', () {
      expect(
        checkCertificatePin(pinned: 'aa', presented: 'aa'),
        CertificatePinCheck.match,
      );
    });

    test('any other certificate is a mismatch', () {
      expect(
        checkCertificatePin(pinned: 'aa', presented: 'ab'),
        CertificatePinCheck.mismatch,
      );
    });
  });

  test('the fingerprint is the SHA-256 of the DER bytes in hex', () {
    expect(
      certificateSha256(_FakeCertificate('abc')),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('a client built for a Quark pins it, then refuses another', () {
    final genuine = _FakeCertificate('genuine');
    final forged = _FakeCertificate('forged');

    expect(acceptsPinnedCertificate(genuine, home), isTrue);
    expect(acceptsPinnedCertificate(genuine, '$home/api/v0/health'), isTrue);
    expect(acceptsPinnedCertificate(forged, home), isFalse);
    expect(AppSettings.instance.certificateChangedFor(home), isTrue);
  });

  test('a client built for no Quark checks the host it is told', () async {
    final genuine = _FakeCertificate('genuine');
    final forged = _FakeCertificate('forged');

    expect(
      acceptsReportedPinnedCertificate(genuine, 'home.local', 443),
      isTrue,
    );
    expect(
      acceptsReportedPinnedCertificate(forged, 'home.local', 443),
      isFalse,
    );
    // iOS reports the resolved address: only a pinned certificate passes.
    expect(acceptsReportedPinnedCertificate(genuine, '10.0.0.7', 443), isTrue);
    expect(acceptsReportedPinnedCertificate(forged, '10.0.0.7', 443), isFalse);

    // Forgetting the pin does not let the next certificate in unseen (#3182).
    await AppSettings.instance.forgetCertificate(home);
    expect(
      acceptsReportedPinnedCertificate(forged, 'home.local', 443),
      isFalse,
    );
    expect(
      AppSettings.instance.pendingCertificateFor(home),
      certificateSha256(forged),
    );
  });
}
