/// The biometric vault key channel on iOS and Android (#3595).
///
/// Only those two have a keystore implementation behind
/// `org.autobutler/vault_keystore`; desktop builds, and tests on a desktop
/// host, answer unavailable without calling it.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quark/services/vault_biometric.dart';

const _channel = MethodChannel(VaultBiometric.channelName);

/// Whether this process runs on iOS or Android, the platforms with a
/// keystore behind the channel. A test of the channel itself sets it.
@visibleForTesting
bool Function() isNativePlatform = () => Platform.isIOS || Platform.isAndroid;

bool get _native => isNativePlatform();

const VaultBiometricSupport _unavailable = (
  availability: VaultBiometricAvailability.unavailable,
  kind: VaultBiometricKind.biometrics,
);

/// Asks the keystore what this device supports. A channel failure reads as
/// unavailable, so a broken keystore never offers biometric unlock.
Future<VaultBiometricSupport> support() async {
  if (!_native) return _unavailable;
  try {
    final answer = await _channel.invokeMapMethod<String, Object?>('support');
    return (
      availability:
          VaultBiometricAvailability.values.asNameMap()[answer?['status']] ??
          VaultBiometricAvailability.unavailable,
      kind:
          VaultBiometricKind.values.asNameMap()[answer?['kind']] ??
          VaultBiometricKind.biometrics,
    );
  } on PlatformException catch (e) {
    debugPrint('[vault_biometric] support check failed: ${e.code}');
    return _unavailable;
  } on MissingPluginException {
    return _unavailable;
  }
}

/// The fingerprint stored beside [account]'s cached key, or null.
Future<Uint8List?> storedFingerprint(String account) async {
  if (!_native) return null;
  return _call(
    () => _channel.invokeMethod<Uint8List>('storedFingerprint', {
      'account': account,
    }),
  );
}

/// Caches [key] for [account] behind the biometric.
Future<void> store(
  String account,
  Uint8List key,
  Uint8List fingerprint,
  VaultBiometricPrompt prompt,
) async {
  if (!_native) {
    throw const VaultBiometricException(VaultBiometricFailure.unavailable);
  }
  await _call(
    () => _channel.invokeMethod<void>('store', {
      'account': account,
      'key': key,
      'fingerprint': fingerprint,
      ..._promptArgs(prompt),
    }),
  );
}

/// Shows the biometric prompt and reads [account]'s cached key.
Future<VaultBiometricEntry> read(
  String account,
  VaultBiometricPrompt prompt,
) async {
  if (!_native) {
    throw const VaultBiometricException(VaultBiometricFailure.unavailable);
  }
  final answer = await _call(
    () => _channel.invokeMapMethod<String, Object?>('read', {
      'account': account,
      ..._promptArgs(prompt),
    }),
  );
  if (answer?['key'] case final Uint8List key) {
    if (answer?['fingerprint'] case final Uint8List fingerprint) {
      return VaultBiometricEntry(key: key, fingerprint: fingerprint);
    }
    key.fillRange(0, key.length, 0);
  }
  throw const VaultBiometricException(VaultBiometricFailure.failed);
}

/// Deletes [account]'s cached key, or every one for null.
Future<void> delete({String? account}) async {
  if (!_native) return;
  await _call(
    () => _channel.invokeMethod<void>('delete', {'account': account}),
  );
}

Map<String, String> _promptArgs(VaultBiometricPrompt prompt) => {
  'title': prompt.title,
  'reason': prompt.reason,
  'cancel': prompt.cancel,
};

/// Runs [call], turning the channel's errors into a
/// [VaultBiometricException]. Only the error code is logged: the channel
/// never puts key material in an error, and nor does this.
Future<T?> _call<T>(Future<T?> Function() call) async {
  try {
    return await call();
  } on PlatformException catch (e) {
    final failure = VaultBiometricException.failureOf(e.code);
    if (failure != VaultBiometricFailure.canceled) {
      debugPrint('[vault_biometric] keystore call failed: ${e.code}');
    }
    throw VaultBiometricException(failure);
  } on MissingPluginException {
    throw const VaultBiometricException(VaultBiometricFailure.unavailable);
  }
}
