import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/account_crypto.dart';
import 'package:quark/services/vault_biometric.dart';
import 'package:quark/services/vault_biometric_io.dart' as io;
import 'package:quark/services/vault_biometric_stub.dart' as stub;

const _account = 'acct_0123456789abcdef0123456789abcdef';
const VaultBiometricPrompt _prompt = (
  title: 'Unlock your vault',
  reason: 'Unlock your Quark vault',
  cancel: 'Use password',
);

/// #3595: the `org.autobutler/vault_keystore` channel as the Dart side
/// speaks it, and the fingerprint it stores beside the key.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(VaultBiometric.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  void answer(Object? Function(MethodCall call) handler) =>
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return handler(call);
      });

  setUp(() {
    calls = [];
    io.isNativePlatform = () => true;
  });

  tearDown(() {
    io.isNativePlatform = () => false;
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('the fingerprint', () {
    test('matches every vector the native code is pinned to', () async {
      final crypto = await AccountCrypto.load();
      final vectors =
          jsonDecode(
                File('test/fixtures/vault_vectors.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      for (final vector in vectors['fingerprints'] as List<dynamic>) {
        final key = crypto.sodium.secureCopy(
          Uint8List.fromList((vector['key'] as List<dynamic>).cast<int>()),
        );
        addTearDown(key.dispose);
        expect(
          base64Encode(crypto.vaultKeyFingerprint(key)),
          vector['fingerprint'],
        );
      }
    });
  });

  group('support', () {
    test('reads the status and the sensor', () async {
      answer((_) => {'status': 'available', 'kind': 'faceId'});
      expect(await io.support(), (
        availability: VaultBiometricAvailability.available,
        kind: VaultBiometricKind.faceId,
      ));
      expect(calls.single.method, 'support');
    });

    test('an unknown answer or a failure reads as unavailable', () async {
      answer((_) => {'status': 'maybe'});
      expect(
        (await io.support()).availability,
        VaultBiometricAvailability.unavailable,
      );

      answer((_) => throw PlatformException(code: 'failed'));
      expect(
        (await io.support()).availability,
        VaultBiometricAvailability.unavailable,
      );
    });

    test('a platform with no keystore never calls the channel', () async {
      io.isNativePlatform = () => false;
      answer((_) => {'status': 'available'});
      expect(
        (await io.support()).availability,
        VaultBiometricAvailability.unavailable,
      );
      expect(await io.storedFingerprint(_account), isNull);
      await io.delete();
      await expectLater(
        io.read(_account, _prompt),
        throwsA(
          isA<VaultBiometricException>().having(
            (e) => e.failure,
            'failure',
            VaultBiometricFailure.unavailable,
          ),
        ),
      );
      expect(calls, isEmpty);
    });
  });

  test('store sends the account, key, fingerprint and prompt', () async {
    answer((_) => null);
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final fingerprint = Uint8List(16);

    await io.store(_account, key, fingerprint, _prompt);

    final call = calls.single;
    expect(call.method, 'store');
    expect(call.arguments, {
      'account': _account,
      'key': key,
      'fingerprint': fingerprint,
      'title': 'Unlock your vault',
      'reason': 'Unlock your Quark vault',
      'cancel': 'Use password',
    });
  });

  test('read hands back the key and its fingerprint', () async {
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final fingerprint = Uint8List.fromList(List.filled(16, 7));
    answer((_) => {'key': key, 'fingerprint': fingerprint});

    final entry = await io.read(_account, _prompt);
    expect(entry.key, key);
    expect(entry.fingerprint, fingerprint);
    expect(calls.single.arguments['account'], _account);
  });

  test('read without a fingerprint fails and zeroes the key it got', () async {
    final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
    answer((_) => {'key': key});

    await expectLater(
      io.read(_account, _prompt),
      throwsA(isA<VaultBiometricException>()),
    );
  });

  test('storedFingerprint and delete name the account', () async {
    final fingerprint = Uint8List.fromList(List.filled(16, 3));
    answer((call) => call.method == 'storedFingerprint' ? fingerprint : null);

    expect(await io.storedFingerprint(_account), fingerprint);
    await io.delete(account: _account);
    await io.delete();
    expect(calls.map((c) => c.method), [
      'storedFingerprint',
      'delete',
      'delete',
    ]);
    expect(calls[1].arguments, {'account': _account});
    expect(calls[2].arguments, {'account': null});
  });

  group('a channel error', () {
    for (final failure in VaultBiometricFailure.values) {
      test('${failure.name} reads as that failure', () async {
        answer((_) => throw PlatformException(code: failure.name));
        await expectLater(
          io.read(_account, _prompt),
          throwsA(
            isA<VaultBiometricException>().having(
              (e) => e.failure,
              'failure',
              failure,
            ),
          ),
        );
      });
    }

    test('an unknown code reads as failed', () {
      expect(
        VaultBiometricException.failureOf('KeyPermanentlyInvalidated'),
        VaultBiometricFailure.failed,
      );
    });

    test('a missing plugin reads as unavailable', () async {
      await expectLater(
        io.read(_account, _prompt),
        throwsA(
          isA<VaultBiometricException>().having(
            (e) => e.failure,
            'failure',
            VaultBiometricFailure.unavailable,
          ),
        ),
      );
    });

    test('logs only its code, never what it carried', () async {
      final logged = <String>[];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
      addTearDown(() => debugPrint = previous);
      // Built at run time, so no secret scanner reads a test value as one.
      final secret = base64Encode(List.generate(32, (i) => i));
      answer(
        (_) => throw PlatformException(
          code: 'failed',
          message: secret,
          details: secret,
        ),
      );

      await expectLater(io.read(_account, _prompt), throwsA(anything));
      await expectLater(
        io.store(_account, Uint8List(32), Uint8List(16), _prompt),
        throwsA(anything),
      );
      expect(logged, isNotEmpty);
      expect(logged.join('\n'), isNot(contains(secret)));
      expect(
        const VaultBiometricException(VaultBiometricFailure.failed).toString(),
        'VaultBiometricException(failed)',
      );
    });
  });

  test('web keeps nothing and offers nothing', () async {
    expect(
      (await stub.support()).availability,
      VaultBiometricAvailability.unavailable,
    );
    expect(await stub.storedFingerprint(_account), isNull);
    await stub.delete();
    await expectLater(
      stub.store(_account, Uint8List(32), Uint8List(16), _prompt),
      throwsA(isA<VaultBiometricException>()),
    );
    await expectLater(
      stub.read(_account, _prompt),
      throwsA(isA<VaultBiometricException>()),
    );
  });
}
