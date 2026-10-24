import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';

void main() {
  group('HostEntry', () {
    test('fromJson reads a missing or null field as an empty string', () {
      for (final json in [
        <String, dynamic>{},
        {'name': null, 'hostAddress': null},
      ]) {
        final entry = HostEntry.fromJson(json);

        expect(entry.name, '', reason: '$json');
        expect(entry.hostAddress, '', reason: '$json');
      }
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
    for (final (address, want) in [
      // A bare hostname, host:port or IP gets https://.
      ('quark.home.local', 'https://quark.home.local'),
      ('quark.home.local:8443', 'https://quark.home.local:8443'),
      ('192.168.1.100', 'https://192.168.1.100'),
      // An explicit scheme, http or not, is left alone.
      ('https://quark.home.local', 'https://quark.home.local'),
      ('http://quark.home.local', 'http://quark.home.local'),
      ('ws://quark.home.local', 'ws://quark.home.local'),
      // The origin-relative web default.
      ('/', '/'),
      ('', ''),
      ('   ', ''),
      // Surrounding whitespace goes before the scheme is added.
      ('  quark.home.local  ', 'https://quark.home.local'),
    ]) {
      test('("$address") is "$want"', () {
        expect(normalizeHostAddress(address), want);
      });
    }

    test('is idempotent', () {
      const bare = 'quark.home.local';
      expect(
        normalizeHostAddress(normalizeHostAddress(bare)),
        normalizeHostAddress(bare),
      );
    });
  });
}
