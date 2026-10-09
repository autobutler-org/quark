import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/emulator_loopback.dart';

/// #2070: the Add Quark forms never said that an Android emulator reaches the
/// developer's machine at `10.0.2.2`, not `localhost`.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('on Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('a loopback address gets the hint', () {
      for (final address in const [
        'http://localhost:8080',
        'https://localhost',
        'https://LOCALHOST:8080/',
        'http://127.0.0.1:8080',
        'http://[::1]:8080',
      ]) {
        expect(emulatorLoopbackHint(address), isNotNull, reason: address);
      }
    });

    test('the hint names the alias to type instead', () {
      final hint = emulatorLoopbackHint('http://localhost:8080');
      expect(hint, contains(emulatorHostAlias));
      expect(hint, contains('localhost'));
    });

    test('any other address gets none', () {
      for (final address in const [
        '',
        'https://quark.local',
        'http://10.0.2.2:8080',
        'https://192.168.1.20',
        'https://localhost.example.com',
        'not a url',
      ]) {
        expect(emulatorLoopbackHint(address), isNull, reason: address);
      }
    });
  });

  test('other platforms get no hint: their localhost is the machine', () {
    for (final platform in const [
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(emulatorLoopbackHint('http://localhost:8080'), isNull);
    }
  });

  test('isLoopbackHost knows the three spellings', () {
    expect(isLoopbackHost('localhost'), isTrue);
    expect(isLoopbackHost('127.0.0.1'), isTrue);
    expect(isLoopbackHost('::1'), isTrue);
    expect(isLoopbackHost('10.0.2.2'), isFalse);
    expect(isLoopbackHost('quark.local'), isFalse);
  });
}
