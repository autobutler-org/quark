import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/device_label.dart';

/// #2051: Connected devices names a client the way its owner would, never
/// by its User-Agent string.
void main() {
  const chromeMac =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
  const dartClient = 'Dart/3.5 (dart:io)';

  group('deviceLabel', () {
    const labels = {
      chromeMac: 'Chrome on macOS',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 '
              'Edg/126.0.0.0':
          'Edge on Windows',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 '
              'OPR/112.0.0.0':
          'Opera on Windows',
      'Mozilla/5.0 (X11; Linux x86_64; rv:127.0) Gecko/20100101 '
              'Firefox/127.0':
          'Firefox on Linux',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
              'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 '
              'Mobile/15E148 Safari/604.1':
          'Safari on iPhone',
      'Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 '
              '(KHTML, like Gecko) CriOS/126.0.0.0 Mobile/15E148 '
              'Safari/604.1':
          'Chrome on iPad',
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36':
          'Chrome on Android',
      'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36':
          'Chrome on ChromeOS',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5)': 'macOS',
      dartClient: 'Quark app',
      'curl/8.7.1': 'curl',
      'exokomodo-bot': 'exokomodo-bot',
      '': 'Unknown device',
    };

    for (final MapEntry(key: userAgent, value: label) in labels.entries) {
      test('"$userAgent" reads as "$label"', () {
        expect(deviceLabel(userAgent), label);
      });
    }
  });

  group('currentDeviceLabel', () {
    test('a browser is "This browser"', () {
      expect(currentDeviceLabel(chromeMac), 'This browser');
    });

    test('anything else is "This device"', () {
      expect(currentDeviceLabel(dartClient), 'This device');
      expect(currentDeviceLabel(''), 'This device');
    });
  });
}
