import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/remote_access_service.dart';

void main() {
  group('RemoteAccessStatus.fromJson', () {
    test('parses a connected Quark', () {
      final status = RemoteAccessStatus.fromJson({
        'enabled': true,
        'connected': true,
        'remoteUrl': 'http://100.64.0.7:80',
      });

      expect(status.enabled, isTrue);
      expect(status.connected, isTrue);
      expect(status.remoteUrl, 'http://100.64.0.7:80');
      expect(status.error, isNull);
    });

    test('keeps enabled apart from connected (#1815)', () {
      final status = RemoteAccessStatus.fromJson({
        'enabled': true,
        'connected': false,
        'error': 'failed to start tsnet: boom',
      });

      expect(status.enabled, isTrue);
      expect(status.connected, isFalse);
      expect(status.remoteUrl, isNull);
      expect(status.error, 'failed to start tsnet: boom');
    });

    test('reads an older Quark without connected as not connected', () {
      final status = RemoteAccessStatus.fromJson({'enabled': true});

      expect(status.enabled, isTrue);
      expect(status.connected, isFalse);
      expect(status.error, isNull);
    });

    test('defaults to off for an empty payload', () {
      final status = RemoteAccessStatus.fromJson({});

      expect(status.enabled, isFalse);
      expect(status.connected, isFalse);
    });
  });
}
