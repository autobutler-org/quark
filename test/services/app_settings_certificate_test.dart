import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/error_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secure_storage.dart';

/// #2721: each saved Quark's self-signed certificate is pinned the first time
/// the app connects, a different one is refused after that, and forgetting
/// the pin lets a re-issued Quark be trusted again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const home = 'https://home.local';
  const first = 'aa11';
  const other = 'bb22';
  final settings = AppSettings.instance;

  setUpAll(mockSecureStorage);

  Future<void> load([Map<String, Object> extra = const {}]) async {
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'Home', 'hostAddress': home},
        {'name': 'Cabin', 'hostAddress': 'https://192.168.1.9:8443'},
      ]),
      'activeHostIndex': 0,
      ...extra,
    });
    await settings.load();
  }

  Future<Map<String, dynamic>> stored() async {
    // The pin is written in the background of a synchronous callback.
    await pumpEventQueue();
    final prefs = await SharedPreferences.getInstance();
    return jsonDecode(prefs.getString('hostCertificates') ?? '{}')
        as Map<String, dynamic>;
  }

  test('the first certificate a saved Quark presents is pinned', () async {
    await load();
    expect(settings.hasCertificateFor(home), isFalse);

    expect(settings.trustCertificate(home, first), isTrue);

    expect(settings.hasCertificateFor(home), isTrue);
    expect(await stored(), {'home.local:443': first});
  });

  test('the pinned certificate keeps being accepted', () async {
    await load();
    settings.trustCertificate(home, first);

    expect(settings.trustCertificate(home, first), isTrue);
    expect(settings.certificateChangedFor(home), isFalse);
  });

  test('a different certificate is refused and reported', () async {
    await load();
    settings.trustCertificate(home, first);
    var notified = 0;
    void listener() => notified++;
    settings.certificatesChanged.addListener(listener);
    addTearDown(() => settings.certificatesChanged.removeListener(listener));

    expect(settings.trustCertificate(home, other), isFalse);

    expect(settings.certificateChangedFor(home), isTrue);
    expect(notified, 1);
    expect(await stored(), {'home.local:443': first}, reason: 'pin unchanged');
    expect(settings.trustCertificate(home, first), isTrue);
  });

  test('a pin survives a restart', () async {
    await load({
      'hostCertificates': jsonEncode({'home.local:443': first}),
    });

    expect(settings.trustCertificate(home, other), isFalse);
    expect(settings.trustCertificate(home, first), isTrue);
  });

  test('the pin follows the server, not the scheme or path', () async {
    await load();
    settings.trustCertificate(home, first);

    expect(
      settings.trustCertificate('wss://HOME.local/api/v0/events', other),
      isFalse,
    );
    expect(
      settings.trustCertificate('https://home.local:443/a.jpg', first),
      isTrue,
    );
  });

  test('another port on the same name is another server', () async {
    await load();
    settings.trustCertificate(home, first);

    expect(settings.trustCertificate('https://home.local:8443', other), isTrue);
    expect(
      settings.hasCertificateFor('https://home.local:8443'),
      isFalse,
      reason: 'not saved, so nothing is pinned',
    );
  });

  test('an address that is not saved is accepted and never pinned', () async {
    await load();

    expect(settings.trustCertificate('https://new.local', first), isTrue);
    expect(settings.trustCertificate('https://new.local', other), isTrue);
    expect(await stored(), isEmpty);
  });

  group('after Forget certificate (#3182)', () {
    test('a new certificate is held for confirmation, not pinned', () async {
      await load();
      settings.trustCertificate(home, first);
      settings.trustCertificate(home, other);

      await settings.forgetCertificate(home);

      expect(settings.certificateChangedFor(home), isFalse);
      expect(settings.hasCertificateFor(home), isFalse);
      expect(settings.forgottenCertificateFor(home), first);
      expect(await stored(), isEmpty);

      expect(settings.trustCertificate(home, other), isFalse);
      expect(settings.pendingCertificateFor(home), other);
      expect(settings.hasCertificateFor(home), isFalse);
      expect(await stored(), isEmpty, reason: 'nothing is pinned blind');
    });

    test('confirming pins the certificate that was presented', () async {
      await load();
      settings.trustCertificate(home, first);
      await settings.forgetCertificate(home);
      settings.trustCertificate(home, other);

      await settings.confirmCertificate(home);

      expect(await stored(), {'home.local:443': other});
      expect(settings.pendingCertificateFor(home), isNull);
      expect(settings.forgottenCertificateFor(home), isNull);
      expect(settings.trustCertificate(home, other), isTrue);
      expect(settings.trustCertificate(home, first), isFalse);
    });

    test('confirming with nothing presented pins nothing', () async {
      await load();
      settings.trustCertificate(home, first);
      await settings.forgetCertificate(home);

      await settings.confirmCertificate(home);

      expect(await stored(), isEmpty);
      expect(settings.trustCertificate(home, other), isFalse);
    });

    test(
      'a restart does not turn the next certificate into a blind pin',
      () async {
        await load();
        settings.trustCertificate(home, first);
        await settings.forgetCertificate(home);

        await load({
          'hostCertificates': (await SharedPreferences.getInstance()).getString(
            'hostCertificates',
          )!,
          'forgottenHostCertificates': (await SharedPreferences.getInstance())
              .getString('forgottenHostCertificates')!,
        });

        expect(settings.trustCertificate(home, other), isFalse);
        expect(settings.pendingCertificateFor(home), other);
      },
    );

    test('the forgotten certificate itself is trusted again', () async {
      await load();
      settings.trustCertificate(home, first);
      await settings.forgetCertificate(home);

      expect(settings.trustCertificate(home, first), isTrue);
      expect(await stored(), {'home.local:443': first});
      expect(settings.forgottenCertificateFor(home), isNull);
    });

    test('removing the Quark drops what was forgotten', () async {
      await load();
      settings.trustCertificate(home, first);
      await settings.forgetCertificate(home);
      settings.trustCertificate(home, other);

      await settings.removeHost(0);
      await settings.addHost(HostEntry(name: 'Home', hostAddress: home));

      expect(settings.pendingCertificateFor(home), isNull);
      expect(settings.forgottenCertificateFor(home), isNull);
      expect(
        settings.trustCertificate(home, other),
        isTrue,
        reason: 'first use',
      );
    });
  });

  test('removing a Quark drops its pin', () async {
    await load();
    settings.trustCertificate(home, first);
    settings.trustCertificate('https://192.168.1.9:8443', other);

    await settings.removeHost(0);

    expect(await stored(), {'192.168.1.9:8443': other});
  });

  test(
    'renaming a saved Quark keeps its pin, a new address does not',
    () async {
      await load();
      settings.trustCertificate(home, first);

      await settings.updateHost(0, HostEntry(name: 'House', hostAddress: home));
      expect(settings.trustCertificate(home, other), isFalse);

      await settings.updateHost(
        0,
        HostEntry(name: 'House', hostAddress: 'https://house.local'),
      );
      expect(await stored(), isEmpty);
      expect(settings.certificateChangedFor(home), isFalse);
    },
  );

  group('a host the TLS layer reports', () {
    test('is held to its own pin when it is a saved Quark', () async {
      await load();

      expect(
        settings.trustReportedCertificate('home.local', 443, first),
        isTrue,
      );
      expect(
        settings.trustReportedCertificate('home.local', 443, other),
        isFalse,
      );
      expect(settings.certificateChangedFor(home), isTrue);
    });

    test('is refused when nothing is pinned (#3182)', () async {
      await load();

      expect(
        settings.trustReportedCertificate('10.0.0.7', 443, other),
        isFalse,
      );
      expect(await stored(), isEmpty);
    });

    test(
      'is refused while the Quark in use is reached without a pin (#3182)',
      () async {
        SharedPreferences.setMockInitialValues({
          'hosts': jsonEncode([
            {'name': 'Home', 'hostAddress': 'http://home.local'},
            {'name': 'Cabin', 'hostAddress': 'https://192.168.1.9:8443'},
          ]),
          'activeHostIndex': 0,
        });
        await settings.load();
        settings.trustCertificate('https://192.168.1.9:8443', first);

        expect(
          settings.trustReportedCertificate('10.0.0.7', 443, other),
          isFalse,
        );
        expect(
          settings.trustReportedCertificate('10.0.0.7', 443, first),
          isTrue,
          reason: 'a certificate some saved Quark is pinned to',
        );
      },
    );

    test(
      'must present a pinned certificate once the Quark in use has one',
      () async {
        await load();
        settings.trustCertificate(home, first);

        expect(
          settings.trustReportedCertificate('10.0.0.7', 443, first),
          isTrue,
        );
        expect(
          settings.trustReportedCertificate('10.0.0.7', 443, other),
          isFalse,
        );
        expect(await stored(), {'home.local:443': first});
      },
    );
  });

  group('Errors.message', () {
    test(
      'says the certificate changed once the Quark in use is refused',
      () async {
        await load();
        settings.trustCertificate(home, first);
        final handshake = const HandshakeException('CERTIFICATE_VERIFY_FAILED');
        expect(Errors.message(handshake, 'sign in'), "Couldn't sign in.");

        settings.trustCertificate(home, other);

        expect(Errors.message(handshake, 'sign in'), Errors.certificateChanged);
        expect(
          Errors.message(const ApiException(404), 'load the file'),
          isNot(Errors.certificateChanged),
          reason: 'an answer from the Quark is not a refused handshake',
        );
      },
    );

    test('asks for confirmation while a new certificate waits', () async {
      await load();
      settings.trustCertificate(home, first);
      await settings.forgetCertificate(home);
      settings.trustCertificate(home, other);

      expect(
        Errors.message(
          const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
          'sign in',
        ),
        Errors.certificateUnconfirmed,
      );
    });
  });
}
