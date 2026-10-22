// cspell:words vaultkeystore
import 'package:flutter/foundation.dart';
import 'package:quark/services/vault_biometric_stub.dart'
    if (dart.library.io) 'package:quark/services/vault_biometric_io.dart'
    as impl;

/// Which sensor this device unlocks with, so the copy can name it.
enum VaultBiometricKind {
  /// An iPhone or iPad with Face ID.
  faceId,

  /// An iPhone or iPad with Touch ID.
  touchId,

  /// Android, which does not say whether a phone uses a face or a finger.
  biometrics,
}

/// Whether this device can keep the vault key behind biometrics.
enum VaultBiometricAvailability {
  /// A strong biometric is enrolled and the keystore is hardware-backed.
  available,

  /// The hardware is there, but no face or fingerprint is enrolled, or no
  /// passcode is set.
  notEnrolled,

  /// Web, desktop, an Android before 9, a weak (Class 2) biometric only, or
  /// a keystore with no secure hardware.
  unavailable,
}

/// What [VaultBiometric.support] answers.
typedef VaultBiometricSupport = ({
  VaultBiometricAvailability availability,
  VaultBiometricKind kind,
});

/// The words the system's biometric prompt shows.
typedef VaultBiometricPrompt = ({String title, String reason, String cancel});

/// Why a keystore call did not go through.
enum VaultBiometricFailure {
  /// The user canceled the prompt or chose the password. Not an error.
  canceled,

  /// A face or fingerprint was enrolled or removed, or the passcode turned
  /// off, so the OS made the cached key unusable. The entry is deleted.
  invalidated,

  /// There is no cached key for the account.
  missing,

  /// Too many failed tries; the OS has locked biometrics for now.
  lockedOut,

  /// The key the keystore opened is not the one its fingerprint names, so
  /// it was deleted.
  stale,

  /// This device cannot keep the key behind biometrics.
  unavailable,

  /// Anything else.
  failed,
}

/// A keystore call that did not go through. It carries only the [failure],
/// never key material, so it is safe to log.
class VaultBiometricException implements Exception {
  /// Wraps [failure].
  const VaultBiometricException(this.failure);

  /// Why the call did not go through.
  final VaultBiometricFailure failure;

  /// The failure the platform channel's error [code] names; an unknown code
  /// is [VaultBiometricFailure.failed].
  static VaultBiometricFailure failureOf(String code) =>
      VaultBiometricFailure.values.asNameMap()[code] ??
      VaultBiometricFailure.failed;

  @override
  String toString() => 'VaultBiometricException(${failure.name})';
}

/// A cached vault key as the keystore hands it back after a biometric
/// check: the 32-byte [key] and the [fingerprint] it was stored with.
/// [toString] never prints either.
class VaultBiometricEntry {
  /// Wraps [key] and its stored [fingerprint].
  const VaultBiometricEntry({required this.key, required this.fingerprint});

  /// The vault key's bytes. Whoever takes them zeroes them.
  final Uint8List key;

  /// What [key]'s fingerprint was when it was stored.
  final Uint8List fingerprint;

  @override
  String toString() => 'VaultBiometricEntry(${key.length} bytes)';
}

/// The vault key in the platform keystore behind biometrics (#3595), over
/// the `org.autobutler/vault_keystore` channel
/// (`docs/design/native-autofill-vault.md`, Decision 2).
///
/// iOS keeps it in a Keychain item with `.biometryCurrentSet` access control,
/// `WhenPasscodeSetThisDeviceOnly`, in the access group the autofill
/// extension will share (`ios/Runner/VaultKeychain.swift`). Android wraps it
/// under an `AndroidKeyStore` AES key that needs a strong biometric for
/// every use and is invalidated by a new enrollment
/// (`org.autobutler.vaultkeystore.VaultKeystore`). Each entry is named by
/// the account key `VaultCache.accountKey` gives, and holds the key's
/// fingerprint beside it, which reads without a prompt.
///
/// Every call fails with a [VaultBiometricException]. Web and desktop have no
/// keystore channel: [support] answers unavailable and nothing is stored.
abstract final class VaultBiometric {
  /// The platform channel's name.
  static const channelName = 'org.autobutler/vault_keystore';

  /// Whether this device can keep the key, and which sensor it has.
  static Future<VaultBiometricSupport> support() => impl.support();

  /// The fingerprint stored for [account], read without a prompt, or null
  /// when nothing is cached for it.
  static Future<Uint8List?> storedFingerprint(String account) =>
      impl.storedFingerprint(account);

  /// Caches [key], whose fingerprint is [fingerprint], for [account],
  /// replacing every other account's. Android shows [prompt], since sealing
  /// under its key needs the biometric too; iOS asks nothing until a read.
  static Future<void> store(
    String account,
    Uint8List key,
    Uint8List fingerprint,
    VaultBiometricPrompt prompt,
  ) => impl.store(account, key, fingerprint, prompt);

  /// Shows [prompt] and hands back [account]'s cached key.
  static Future<VaultBiometricEntry> read(
    String account,
    VaultBiometricPrompt prompt,
  ) => impl.read(account, prompt);

  /// Deletes [account]'s cached key, or every account's for null.
  static Future<void> delete({String? account}) =>
      impl.delete(account: account);
}
