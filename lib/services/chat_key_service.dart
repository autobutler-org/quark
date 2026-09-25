import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/models/chat_keys.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The chat key routes (#2416): the caller's wrapped identity under
/// `/api/v0/chat/keys/me` and anyone's public keys under
/// `/api/v0/chat/keys/:id`. Recovery's fetch, which has no session, is
/// `AuthService.fetchRecoveryChatKeys`.
///
/// Everything here is ciphertext or public keys; `ChatCrypto` does the crypto.
class ChatKeyService with AuthenticatedService {
  ChatKeyService._();

  /// The one instance, for the [AuthenticatedService] helpers.
  static final ChatKeyService instance = ChatKeyService._();

  /// The signed-in account's wrapped identity, or null when it has none yet.
  ///
  /// [sessionToken] is for a session the app hasn't stored yet: a first
  /// sign-in whose recovery phrase is still on screen.
  static Future<WrappedChatKeys?> fetchMine({String? sessionToken}) async {
    final response = await instance.authenticatedGet(
      _uri('/me'),
      headers: _bearer(sessionToken),
    );
    if (response.statusCode == 404) return null;
    _check(response, 'fetch chat keys');
    return WrappedChatKeys.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Stores [keys] as the signed-in account's identity, replacing any.
  static Future<void> putMine(
    WrappedChatKeys keys, {
    String? sessionToken,
  }) async {
    final response = await instance.authenticatedPut(
      _uri('/me'),
      headers: {'Content-Type': 'application/json', ..._bearer(sessionToken)},
      body: jsonEncode(keys.toJson()),
    );
    _check(response, 'store chat keys');
  }

  /// Account [userId]'s public keys, or null when it has none yet or isn't an
  /// active account.
  static Future<ChatPublicKeys?> fetchPublic(int userId) async {
    final response = await instance.authenticatedGet(_uri('/$userId'));
    if (response.statusCode == 404) return null;
    _check(response, 'fetch chat keys of $userId');
    return ChatPublicKeys.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Map<String, String> _bearer(String? token) =>
      token == null ? const {} : {'Authorization': 'Bearer $token'};

  static Uri _uri(String suffix) =>
      apiBaseUri.resolve('/api/v0/chat/keys$suffix');

  static void _check(http.Response response, String context) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    Object? error;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) error = decoded['error'];
    } on FormatException {
      error = null;
    }
    throwApiError(status, error, context);
  }
}
