import 'dart:typed_data';

import 'package:quark/models/chat_keys.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/utils/error_text.dart';

/// What a request is about to do with a password, which decides what an
/// account the Quark marks `legacy` is sent.
enum AuthSecretUse {
  /// `POST /auth/login`. An account with no auth key yet is sent both the
  /// password and the key, once, which moves it to the key.
  signIn,

  /// Proving the password again inside a session: deleting the account, a
  /// drive's role, a snapshot backup, the vault's storage location. The Quark
  /// checks only an auth key there, so an account with none yet is refused
  /// until it signs in again through the form.
  reconfirm,

  /// A credential being set: setup, an account request, an admin creating an
  /// account, a recovery's new password. Nothing has to be proven, so the
  /// auth key goes alone whether or not the account had one.
  newCredential,
}

/// What the app sends a Quark in a password's place (#2430), and the one
/// place that decides it.
///
/// The app derives an auth key from the password and the account's salt
/// ([ChatCrypto.deriveAuthKeys]) and sends that, so the Quark never holds the
/// password or anything that opens the chat keys. [resolve] asks
/// `GET /auth/salt` and then:
///
/// - the Quark has no salt endpoint, or does not report `legacyRecovery`, so
///   it is too old to take keys: [Errors.quarkTooOld], and nothing is sent.
/// - the account has an auth key: [authKey] alone.
/// - the account has none yet (`legacy`): both [password] and [authKey] for
///   [AuthSecretUse.signIn], which is the one time the password goes out;
///   [Errors.accountTooOld] for [AuthSecretUse.reconfirm]; [authKey] alone
///   for [AuthSecretUse.newCredential].
///
/// The app believes the `legacy` answer every time: it cannot tell a Quark
/// that was reset or reinstalled from one that was tampered with, so a
/// compromised Quark can collect the password this way (docs/chat-security.md).
class AuthSecret {
  const AuthSecret._({
    this.password,
    required this.authKey,
    required this.salt,
    required this.legacyRecovery,
  });

  /// The raw password, set only for the one sign-in that upgrades a `legacy`
  /// account.
  final String? password;

  /// The auth key, standard base64 of 32 bytes.
  final String authKey;

  /// The salt [authKey] was derived with, which the chat keys' password wrap
  /// and the recovery key are derived with too.
  final Uint8List salt;

  /// Whether the account has no recovery key yet, as the salt endpoint said.
  final bool legacyRecovery;

  /// Decides what to send for [username]'s [password]. See the class doc.
  ///
  /// [username] goes to the salt endpoint exactly as it will go in the
  /// request: the Quark matches it without folding case.
  static Future<AuthSecret> resolve({
    required String username,
    required String password,
    required AuthSecretUse use,
  }) async {
    final answer = await AuthService.fetchAuthSalt(username);
    final legacyRecovery = answer?.legacyRecovery;
    if (answer == null || legacyRecovery == null) {
      throw const MessageException(Errors.quarkTooOld);
    }
    final upgrade = answer.legacy && use == AuthSecretUse.signIn;
    if (answer.legacy && use == AuthSecretUse.reconfirm) {
      throw const MessageException(Errors.accountTooOld);
    }
    final crypto = await ChatCrypto.load();
    final keys = crypto.deriveAuthKeys(
      password,
      answer.salt,
      KdfParams.standard,
    );
    // Only the auth key is wanted here; the chat keys derive their own.
    keys.dispose();
    return AuthSecret._(
      password: upgrade ? password : null,
      authKey: keys.authKey,
      salt: answer.salt,
      legacyRecovery: legacyRecovery,
    );
  }
}
