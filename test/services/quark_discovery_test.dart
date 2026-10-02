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

  // #2518: a router that appends .lan answers for quark.lan in its own DNS
  // while mDNS answers for quark.local, and a phone may reach only one.
  group('localNameVariants', () {
    test('a .local name also tries .lan and the bare name', () {
      expect(localNameVariants('https://quark.local'), [
        'https://quark.lan',
        'https://quark',
      ]);
    });

    test('a .lan name also tries .local and the bare name', () {
      expect(localNameVariants('https://quark.lan'), [
        'https://quark.local',
        'https://quark',
      ]);
    });

    test('a bare name tries both suffixes', () {
      expect(localNameVariants('https://quark'), [
        'https://quark.local',
        'https://quark.lan',
      ]);
    });

    test('a name the router stacked .lan onto loses both suffixes', () {
      expect(localNameVariants('https://quark.local.lan'), [
        'https://quark.local',
        'https://quark.lan',
        'https://quark',
      ]);
    });

    test('the scheme and port are kept', () {
      expect(localNameVariants('http://Quark.local:8443'), [
        'http://quark.lan:8443',
        'http://quark:8443',
      ]);
    });

    test('an IP address, a public name and localhost have none', () {
      expect(localNameVariants('https://192.168.1.20'), isEmpty);
      expect(localNameVariants('https://[fd00::20]'), isEmpty);
      expect(localNameVariants('https://quark.example.com'), isEmpty);
      expect(localNameVariants('http://localhost:8099'), isEmpty);
      expect(localNameVariants('/'), isEmpty);
    });
  });

  group('firstReachableAddress', () {
    late List<String> probed;
    Future<bool> Function(String) answersOn(Set<String> live) =>
        (address) async {
          probed.add(address);
          return live.contains(address);
        };

    setUp(() => probed = []);

    test('the typed address wins and nothing else is asked', () async {
      final found = await firstReachableAddress(
        'https://quark.local',
        answersOn({'https://quark.local', 'https://quark.lan'}),
      );
      expect(found, 'https://quark.local');
      expect(probed, ['https://quark.local']);
    });

    test('a .local the phone cannot resolve falls back to .lan', () async {
      final found = await firstReachableAddress(
        'https://quark.local',
        answersOn({'https://quark.lan'}),
      );
      expect(found, 'https://quark.lan');
    });

    test('the first variant in order wins when several answer', () async {
      final found = await firstReachableAddress(
        'https://quark',
        answersOn({'https://quark.lan', 'https://quark.local'}),
      );
      expect(found, 'https://quark.local');
    });

    test('null when no name answers', () async {
      final found = await firstReachableAddress(
        'https://quark.local',
        answersOn({}),
      );
      expect(found, isNull);
      expect(probed, [
        'https://quark.local',
        'https://quark.lan',
        'https://quark',
      ]);
    });
  });
}
