import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';

void main() {
  group('HostEntry', () {
    test('toJson returns correct map', () {
      final entry = HostEntry(
        name: 'Local',
        hostAddress: 'http://localhost:8080',
      );
      final json = entry.toJson();

      expect(json, {'name': 'Local', 'hostAddress': 'http://localhost:8080'});
    });

    test('fromJson parses name and hostAddress', () {
      final entry = HostEntry.fromJson({
        'name': 'Remote',
        'hostAddress': 'https://butler.example.com',
      });

      expect(entry.name, 'Remote');
      expect(entry.hostAddress, 'https://butler.example.com');
    });

    test('fromJson defaults missing fields to empty strings', () {
      final entry = HostEntry.fromJson({});

      expect(entry.name, '');
      expect(entry.hostAddress, '');
    });

    test('fromJson handles null values gracefully', () {
      final entry = HostEntry.fromJson({'name': null, 'hostAddress': null});

      expect(entry.name, '');
      expect(entry.hostAddress, '');
    });

    test('roundtrip: toJson -> fromJson preserves values', () {
      final original = HostEntry(
        name: 'Pi',
        hostAddress: 'http://192.168.1.100:80',
      );
      final restored = HostEntry.fromJson(original.toJson());

      expect(restored.name, original.name);
      expect(restored.hostAddress, original.hostAddress);
    });

    test('fromJson with extra keys ignores them', () {
      final entry = HostEntry.fromJson({
        'name': 'Test',
        'hostAddress': 'http://test.local',
        'extraField': 42,
        'anotherOne': true,
      });

      expect(entry.name, 'Test');
      expect(entry.hostAddress, 'http://test.local');
    });

    // #1880: the remote-access address is optional and must not change how a
    // host without one is saved or loaded.
    test('a host saved before remoteAddress existed loads without one', () {
      final entry = HostEntry.fromJson({
        'name': 'Pi',
        'hostAddress': 'https://quark.local',
      });

      expect(entry.remoteAddress, isNull);
    });

    test('toJson leaves remoteAddress out while there is none', () {
      final json = HostEntry(
        name: 'Pi',
        hostAddress: 'https://quark.local',
      ).toJson();

      expect(json.containsKey('remoteAddress'), isFalse);
    });

    test('roundtrip preserves remoteAddress', () {
      final original = HostEntry(
        name: 'Pi',
        hostAddress: 'https://quark.local',
        remoteAddress: 'http://100.64.0.7:80',
      );
      final restored = HostEntry.fromJson(original.toJson());

      expect(restored.name, original.name);
      expect(restored.hostAddress, original.hostAddress);
      expect(restored.remoteAddress, 'http://100.64.0.7:80');
    });

    test('fromJson reads an empty or mistyped remoteAddress as none', () {
      for (final value in ['', 42, null]) {
        final entry = HostEntry.fromJson({
          'name': 'Pi',
          'hostAddress': 'https://quark.local',
          'remoteAddress': value,
        });
        expect(entry.remoteAddress, isNull, reason: '$value');
      }
    });
  });

  group('AppSettings.setRemoteAddress', () {
    final settings = AppSettings.instance;

    Future<void> clearHosts() async {
      while (settings.hosts.isNotEmpty) {
        await settings.removeHost(settings.hosts.length - 1);
      }
    }

    setUp(clearHosts);
    tearDown(clearHosts);

    test('records and clears the address on the matching host only', () async {
      await settings.addHost(
        HostEntry(name: 'One', hostAddress: 'https://one.local'),
      );
      await settings.addHost(
        HostEntry(name: 'Two', hostAddress: 'https://two.local'),
      );

      await settings.setRemoteAddress(
        'https://ONE.local/',
        'http://100.64.0.7:80',
      );
      expect(settings.hosts[0].remoteAddress, 'http://100.64.0.7:80');
      expect(settings.hosts[0].name, 'One');
      expect(settings.hosts[1].remoteAddress, isNull);

      await settings.setRemoteAddress('https://one.local', null);
      expect(settings.hosts[0].remoteAddress, isNull);
    });
  });

  group('normalizeHostAddress', () {
    test('prepends https:// to a bare hostname', () {
      expect(
        normalizeHostAddress('quark.home.local'),
        'https://quark.home.local',
      );
    });

    test('prepends https:// to a bare host:port', () {
      expect(
        normalizeHostAddress('quark.home.local:8443'),
        'https://quark.home.local:8443',
      );
    });

    test('prepends https:// to a bare IP address', () {
      expect(normalizeHostAddress('192.168.1.100'), 'https://192.168.1.100');
    });

    test('leaves an explicit https:// address untouched', () {
      expect(
        normalizeHostAddress('https://quark.home.local'),
        'https://quark.home.local',
      );
    });

    test('leaves an explicit http:// address untouched', () {
      expect(
        normalizeHostAddress('http://quark.home.local'),
        'http://quark.home.local',
      );
    });

    test('leaves a non-http scheme untouched', () {
      expect(
        normalizeHostAddress('ws://quark.home.local'),
        'ws://quark.home.local',
      );
    });

    test('leaves the origin-relative web default untouched', () {
      expect(normalizeHostAddress('/'), '/');
    });

    test('leaves an empty address empty', () {
      expect(normalizeHostAddress(''), '');
      expect(normalizeHostAddress('   '), '');
    });

    test('trims surrounding whitespace before adding the scheme', () {
      expect(
        normalizeHostAddress('  quark.home.local  '),
        'https://quark.home.local',
      );
    });

    test('is idempotent', () {
      const bare = 'quark.home.local';
      expect(
        normalizeHostAddress(normalizeHostAddress(bare)),
        normalizeHostAddress(bare),
      );
    });
  });
}
