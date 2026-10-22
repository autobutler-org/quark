/// Web stand-in for the biometric vault key channel (#3595). A browser has
/// no keystore to keep the key in, so biometric unlock is unavailable and
/// nothing is stored. This file does not call `dart:io`.
library;

import 'package:flutter/foundation.dart';
import 'package:quark/services/vault_biometric.dart';

/// Always unavailable on web.
Future<VaultBiometricSupport> support() async => (
  availability: VaultBiometricAvailability.unavailable,
  kind: VaultBiometricKind.biometrics,
);

/// Nothing is cached on web.
Future<Uint8List?> storedFingerprint(String account) async => null;

/// Refuses: there is nowhere to keep the key.
Future<void> store(
  String account,
  Uint8List key,
  Uint8List fingerprint,
  VaultBiometricPrompt prompt,
) async =>
    throw const VaultBiometricException(VaultBiometricFailure.unavailable);

/// Refuses: nothing is cached.
Future<VaultBiometricEntry> read(
  String account,
  VaultBiometricPrompt prompt,
) async =>
    throw const VaultBiometricException(VaultBiometricFailure.unavailable);

/// Does nothing on web.
Future<void> delete({String? account}) async {}
