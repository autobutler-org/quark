import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/connected_devices_service.dart';

void main() {
  group('ConnectedDevice.fromJson', () {
    test('parses a complete JSON payload', () {
      final json = {
        'id': 42,
        'ipAddress': '192.168.1.100',
        'userAgent': 'exokomodo-bot',
        'firstSeenAt': '2026-03-20T10:30:00Z',
        'lastSeenAt': '2026-03-24T22:00:00Z',
        'requestCount': 1500,
      };

      final device = ConnectedDevice.fromJson(json);

      expect(device.id, 42);
      expect(device.ipAddress, '192.168.1.100');
      expect(device.userAgent, 'exokomodo-bot');
      expect(device.firstSeenAt, DateTime.utc(2026, 3, 20, 10, 30));
      expect(device.lastSeenAt, DateTime.utc(2026, 3, 24, 22));
      expect(device.requestCount, 1500);
      expect(device.current, isFalse);
    });

    test('reads current, which marks the caller\'s own row (#2051)', () {
      final device = ConnectedDevice.fromJson({
        'id': 1,
        'ipAddress': '10.0.0.1',
        'firstSeenAt': '2026-01-01T00:00:00Z',
        'lastSeenAt': '2026-01-01T00:00:00Z',
        'requestCount': 0,
        'current': true,
      });

      expect(device.current, isTrue);
    });

    test('defaults userAgent to empty string when null', () {
      final json = {
        'id': 1,
        'ipAddress': '10.0.0.1',
        'userAgent': null,
        'firstSeenAt': '2026-01-01T00:00:00Z',
        'lastSeenAt': '2026-01-01T00:00:00Z',
        'requestCount': 0,
      };

      final device = ConnectedDevice.fromJson(json);
      expect(device.userAgent, '');
    });

    test('defaults userAgent to empty string when missing', () {
      final json = {
        'id': 1,
        'ipAddress': '10.0.0.1',
        'firstSeenAt': '2026-01-01T00:00:00Z',
        'lastSeenAt': '2026-01-01T00:00:00Z',
        'requestCount': 0,
      };

      final device = ConnectedDevice.fromJson(json);
      expect(device.userAgent, '');
    });

    test('throws on missing required fields', () {
      expect(() => ConnectedDevice.fromJson({}), throwsA(isA<TypeError>()));
    });

    test('throws on malformed date strings', () {
      final json = {
        'id': 1,
        'ipAddress': '10.0.0.1',
        'firstSeenAt': 'not-a-date',
        'lastSeenAt': '2026-01-01T00:00:00Z',
        'requestCount': 0,
      };

      expect(
        () => ConnectedDevice.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
