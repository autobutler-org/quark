import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/quark_discovery.dart';

/// The address a Quark found on the network fills in (#2312): the host the
/// platform resolved, over https, with the port only when it is not 443.
void main() {
  String? address(String? host, [int port = 443]) => discoveredQuark(
    name: 'Quark on quark',
    host: host,
    port: port,
  )?.hostAddress;

  test('an SRV target loses its trailing dot', () {
    expect(address('quark-2.local.'), 'https://quark-2.local');
  });

  test('an IPv4 address is used as it is', () {
    expect(address('192.168.1.20'), 'https://192.168.1.20');
  });

  test('an IPv6 address is bracketed', () {
    expect(address('fd00::20'), 'https://[fd00::20]');
  });

  test('a port other than 443 is kept', () {
    expect(address('quark.local', 8443), 'https://quark.local:8443');
  });

  test('a service with no usable host is skipped', () {
    expect(address(null), isNull);
    expect(address(''), isNull);
    expect(address('fe80::1%en0'), isNull);
  });

  test('the entry is named after the service', () {
    final entry = discoveredQuark(
      name: 'Quark on quark-2',
      host: 'quark-2.local',
      port: 443,
    );
    expect(entry?.name, 'Quark on quark-2');
  });
}
