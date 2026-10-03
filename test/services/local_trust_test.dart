import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/local_trust.dart';
import 'package:quark/services/local_trust_overrides_io.dart';

void main() {
  group('isLocalTrustHost', () {
    test('trusts mDNS .local hostnames', () {
      expect(isLocalTrustHost('openclaw.local'), isTrue);
      expect(isLocalTrustHost('quark.home.local'), isTrue);
      expect(isLocalTrustHost('OpenClaw.Local'), isTrue);
    });

    test('trusts other private-network suffixes', () {
      expect(isLocalTrustHost('butler.lan'), isTrue);
      expect(isLocalTrustHost('butler.home'), isTrue);
      expect(isLocalTrustHost('butler.home.arpa'), isTrue);
      expect(isLocalTrustHost('butler.internal'), isTrue);
    });

    test('trusts single-label hostnames', () {
      expect(isLocalTrustHost('openclaw'), isTrue);
      expect(isLocalTrustHost('localhost'), isTrue);
    });

    test('trusts RFC 1918 IPv4 ranges', () {
      expect(isLocalTrustHost('192.168.1.10'), isTrue);
      expect(isLocalTrustHost('10.0.2.2'), isTrue);
      expect(isLocalTrustHost('10.1.2.3'), isTrue);
      expect(isLocalTrustHost('172.16.0.1'), isTrue);
      expect(isLocalTrustHost('172.31.255.254'), isTrue);
      expect(isLocalTrustHost('127.0.0.1'), isTrue);
      expect(isLocalTrustHost('169.254.1.1'), isTrue);
    });

    test('rejects public IPv4 near the private ranges', () {
      expect(isLocalTrustHost('172.15.0.1'), isFalse);
      expect(isLocalTrustHost('172.32.0.1'), isFalse);
      expect(isLocalTrustHost('192.169.1.1'), isFalse);
      expect(isLocalTrustHost('11.0.0.1'), isFalse);
      expect(isLocalTrustHost('8.8.8.8'), isFalse);
    });

    test('trusts loopback, link-local, and unique-local IPv6', () {
      expect(isLocalTrustHost('::1'), isTrue);
      expect(isLocalTrustHost('fe80::1'), isTrue);
      expect(isLocalTrustHost('fe80::1%en0'), isTrue);
      expect(isLocalTrustHost('fd00::1'), isTrue);
      expect(isLocalTrustHost('fc00::1'), isTrue);
    });

    test('rejects public IPv6', () {
      expect(isLocalTrustHost('2001:4860:4860::8888'), isFalse);
    });

    test('rejects public hostnames', () {
      expect(isLocalTrustHost('example.com'), isFalse);
      expect(isLocalTrustHost('quark.io'), isFalse);
      // A public host that merely contains "local" is not a .local host.
      expect(isLocalTrustHost('local.example.com'), isFalse);
      expect(isLocalTrustHost('mylocal.com'), isFalse);
    });

    test('rejects empty and null hosts', () {
      expect(isLocalTrustHost(null), isFalse);
      expect(isLocalTrustHost(''), isFalse);
    });

    test('matches the host parsed out of a configured URL', () {
      expect(
        isLocalTrustHost(Uri.parse('https://openclaw.local:80').host),
        isTrue,
      );
      expect(isLocalTrustHost(Uri.parse('https://example.com').host), isFalse);
    });
  });

  // #2154: a certificate nobody could verify is accepted for a private
  // address, or for a local name the user chose, and nothing else.
  group('acceptsUnverifiedCertificate', () {
    test('accepts private and loopback addresses whatever was chosen', () {
      expect(acceptsUnverifiedCertificate('192.168.1.10', const []), isTrue);
      expect(acceptsUnverifiedCertificate('10.0.2.2', const []), isTrue);
      expect(acceptsUnverifiedCertificate('fe80::1%en0', const []), isTrue);
      expect(acceptsUnverifiedCertificate('localhost', const []), isTrue);
    });

    test('accepts a local name only when it was chosen', () {
      expect(
        acceptsUnverifiedCertificate('quark.local', const ['quark.local']),
        isTrue,
      );
      expect(
        acceptsUnverifiedCertificate('Quark.LAN', const ['quark.lan']),
        isTrue,
      );
      expect(acceptsUnverifiedCertificate('quark', const ['quark']), isTrue);
      expect(
        acceptsUnverifiedCertificate('printer.lan', const ['quark.local']),
        isFalse,
      );
      expect(
        acceptsUnverifiedCertificate('router', const ['quark.local']),
        isFalse,
      );
      expect(acceptsUnverifiedCertificate('nas.internal', const []), isFalse);
    });

    test('never accepts a public or tailnet name, even when chosen', () {
      expect(
        acceptsUnverifiedCertificate('example.com', const ['example.com']),
        isFalse,
      );
      expect(
        acceptsUnverifiedCertificate('quark.tail1234.ts.net', const [
          'quark.tail1234.ts.net',
        ]),
        isFalse,
      );
      expect(acceptsUnverifiedCertificate('100.64.0.1', const []), isFalse);
    });

    test('rejects empty and null hosts', () {
      expect(acceptsUnverifiedCertificate(null, const ['']), isFalse);
      expect(acceptsUnverifiedCertificate('', const ['']), isFalse);
    });
  });

  group('LocalTrustHttpOverrides', () {
    LocalTrustHttpOverrides withSaved(List<String?> addresses) =>
        LocalTrustHttpOverrides(chosenAddresses: () => addresses);

    test('trusts the saved local hosts and private addresses', () {
      final overrides = withSaved([
        'https://quark.local',
        'https://quark.lan:8443',
      ]);
      expect(overrides.trusts('quark.local'), isTrue);
      expect(overrides.trusts('quark.lan'), isTrue);
      expect(overrides.trusts('192.168.1.10'), isTrue);
    });

    test('a local active host does not extend trust to other hosts', () {
      final overrides = withSaved(['https://quark.local']);
      expect(overrides.trusts('example.com'), isFalse);
      expect(overrides.trusts('quark.tail1234.ts.net'), isFalse);
      expect(overrides.trusts('printer.lan'), isFalse);
    });

    test('reads remote and unparseable addresses without throwing', () {
      final overrides = withSaved([null, '', 'https://[fe80::1]', '::::']);
      expect(overrides.trusts('fe80::1'), isTrue);
      expect(overrides.trusts('quark.local'), isFalse);
    });
  });
}
