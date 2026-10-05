import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/models/chat_keys.dart';
import 'package:quark/services/chat_crypto.dart';

/// The salt [AuthSaltClient] hands every username.
final Uint8List testAuthSalt = Uint8List.fromList(List.generate(16, (i) => i));

/// The auth key the app derives from [password] and [testAuthSalt], as it
/// goes on the wire. Real libsodium at the shipped cost.
Future<String> testAuthKey(String password) async {
  final keys = (await ChatCrypto.load()).deriveAuthKeys(
    password,
    testAuthSalt,
    KdfParams.standard,
  );
  keys.dispose();
  return keys.authKey;
}

/// The recovery key the app derives from [phrase] and [testAuthSalt], as it
/// goes on the wire.
Future<String> testRecoveryKey(String phrase) async {
  final keys = (await ChatCrypto.load()).deriveRecoveryKeys(
    phrase,
    testAuthSalt,
    KdfParams.standard,
  );
  keys.dispose();
  return keys.authKey;
}

/// A Quark's `GET /api/v0/auth/salt` (#2430) in front of [inner], which gets
/// every other request and so records none of the salt lookups.
///
/// [status] other than 200 is a Quark that has not updated: 404, or the 401
/// it gives an unknown API path. [legacy] is an account with no auth key, and
/// [legacyRecovery] one with no recovery key; null leaves the field out, as a
/// Quark from before recovery keys does.
class AuthSaltClient extends http.BaseClient {
  /// Fronts [inner].
  AuthSaltClient(
    this.inner, {
    this.legacy = false,
    this.legacyRecovery = false,
    this.status = 200,
  });

  /// Answers everything but the salt.
  final http.Client inner;

  /// Whether the account is reported as having no auth key yet.
  bool legacy;

  /// Whether the account is reported as having no recovery key yet.
  bool? legacyRecovery;

  /// The salt endpoint's status.
  int status;

  /// The usernames a salt was asked for, in order.
  final asked = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path != '/api/v0/auth/salt') return inner.send(request);
    asked.add(request.url.queryParameters['username']!);
    final body = status == 200
        ? jsonEncode({
            'salt': base64Encode(testAuthSalt),
            'legacy': legacy,
            'legacyRecovery': ?legacyRecovery,
          })
        : '{"error":"not found"}';
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      request: request,
    );
  }
}

/// Pumps [tester] while a sign-in, setup or recovery derives its keys, which
/// needs the real event loop as well as the fake clock (#2430). Call it after
/// the tap that starts the request and before `pumpAndSettle`, which would
/// otherwise time out on the spinner.
Future<void> pumpWhileDeriving(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}
