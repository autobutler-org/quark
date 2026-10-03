import 'dart:typed_data';

import 'package:quark/models/chat_keys.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/utils/error_text.dart';

/// What a request is about to do with a password, which decides whether a
/// Quark that still wants the raw password gets it.
enum AuthSecretUse {
  /// `POST /auth/login`. An account with no auth key yet is sent both the
  /// password and the key, once, which gives it one.
  signIn,

  /// A credential being set: setup, an account request, an admin creating an
  /// account, a recovery's new password. Nothing has to be proven, so the
  /// auth key goes alone whether or not the account had one.
  newCredential,

  /// Proving the password again inside a session: deleting the account, a
  /// drive's role, a snapshot backup, the vault's storage location. An account
  /// with no auth key yet can only be checked by its password.
  reconfirm,
}

/// What the app sends a Quark in a password's place (#2430), and the one
/// place that decides it.
///
/// The app derives an auth key from the password and the account's salt
/// ([ChatCrypto.deriveAuthKeys]) and sends that, so a Quark that records a
/// sign-in never holds the password or anything that opens the chat keys.
/// [resolve] asks `GET /auth/salt` and then:
///
/// - the account has an auth key: [authKey] alone.
/// - the account has none yet (`legacy`): both for [AuthSecretUse.signIn],
///   the [password] alone for [AuthSecretUse.reconfirm], [authKey] alone for
///   [AuthSecretUse.newCredential].
/// - the Quark has no salt endpoint, because it has not updated yet: the
///   [password] alone, as before.
///
/// Once an account has signed in to a Quark with an auth key
/// ([AppSettings.signsInWithAuthKey]), the last two no longer send the
/// password: they throw [Errors.passwordDowngradeRefused], since a Quark that
/// was tampered with could claim either to collect it.
class AuthSecret {
  const AuthSecret._({
    this.password,
    this.authKey,
    this.salt,
    this.legacyRecovery,
  });

  /// The raw password, when this request still has to carry it.
  final String? password;

  /// The auth key, standard base64 of 32 bytes, when one was derived.
  final String? authKey;

  /// The salt [authKey] was derived with, which the chat keys' password wrap
  /// is derived with too. Null when the Quark has no salt endpoint.
  final Uint8List? salt;

  /// What the salt endpoint said of the account's recovery phrase: true for
  /// no recovery key yet, false for one, null when it did not say, as a Quark
  /// from before recovery keys does not (#2430).
  final bool? legacyRecovery;

  /// What goes in a re-confirmation's `password` field, which takes either.
  String get confirmation => password ?? authKey!;

  /// The credential fields of a request body, under the names its endpoint
  /// reads.
  Map<String, String> fields({
    String passwordField = 'password',
    String authKeyField = 'authKey',
  }) => {passwordField: ?password, authKeyField: ?authKey};

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
    final sendsPassword =
        answer == null || (answer.legacy && use != AuthSecretUse.newCredential);
    if (sendsPassword && AppSettings.instance.signsInWithAuthKey(username)) {
      throw const MessageException(Errors.passwordDowngradeRefused);
    }
    if (answer == null || (answer.legacy && use == AuthSecretUse.reconfirm)) {
      return AuthSecret._(password: password);
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
      password: sendsPassword ? password : null,
      authKey: keys.authKey,
      salt: answer.salt,
      legacyRecovery: answer.legacyRecovery,
    );
  }

  /// Records that the Quark accepted this secret for [username], which is what
  /// arms the refusal in [resolve]. Call it after a request that returned a
  /// session.
  ///
  /// A sign-in that carried the password too only asked for an auth key to be
  /// stored, and the Quark signs in even when storing it failed. So that case
  /// is recorded only once the salt endpoint says the account has one.
  Future<void> accepted(String username) async {
    if (authKey == null) return;
    if (password != null) {
      try {
        if ((await AuthService.fetchAuthSalt(username))?.legacy != false) {
          return;
        }
      } catch (_) {
        // The sign-in stands; the next one records it.
        return;
      }
    }
    await AppSettings.instance.rememberAuthKeySignIn(username);
  }
}
