import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The channel key and event routes under `/api/v0/chat/channels/:id` (#2417):
/// key versions and this account's grants, the grants it can fill, uploading
/// them, creating a version, and the channel's signed system events.
///
/// Everything here is sealed keys, signatures and public keys;
/// `ChatChannelKeysController` does the crypto.
class ChatChannelKeysService with AuthenticatedService {
  ChatChannelKeysService._();

  /// The one instance, for the [AuthenticatedService] helpers.
  static final ChatChannelKeysService instance = ChatChannelKeysService._();

  /// Channel [channelId]'s key versions and this account's grants.
  static Future<ChatChannelKeys> fetchKeys(int channelId) async {
    final response = await instance.authenticatedGet(_uri(channelId, '/keys'));
    _check(response, 'fetch keys of channel $channelId');
    return ChatChannelKeys.fromJson(_json(response));
  }

  /// Creates [version] with this account's own grant of it, and returns the
  /// `key_created` event to sign; null when another member created it first.
  static Future<ChatChannelEvent?> createVersion(
    int channelId,
    int version,
    Uint8List sealedKey,
    Uint8List signature,
  ) async {
    final response = await instance.authenticatedPost(
      _uri(channelId, '/keys'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'version': version,
        'sealedKey': base64Encode(sealedKey),
        'signature': base64Encode(signature),
      }),
    );
    if (response.statusCode == 409) return null;
    _check(response, 'create key $version of channel $channelId');
    return ChatChannelEvent.fromJson(
      _json(response)['event'] as Map<String, dynamic>,
    );
  }

  /// The grants this account holds the key to fill.
  static Future<ChatPendingGrants> fetchPending(int channelId) async {
    final response = await instance.authenticatedGet(
      _uri(channelId, '/keys/pending'),
    );
    _check(response, 'fetch pending grants of channel $channelId');
    return ChatPendingGrants.fromJson(_json(response));
  }

  /// Uploads [grants]. The Quark keeps the first grant per member and
  /// version, so a duplicate is harmless.
  static Future<void> uploadGrants(
    int channelId,
    List<ChatGrantUpload> grants,
  ) async {
    final response = await instance.authenticatedPost(
      _uri(channelId, '/keys/grants'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'grants': [for (final g in grants) g.toJson()],
      }),
    );
    _check(response, 'upload grants of channel $channelId');
  }

  /// The channel's events after [after], oldest first, at most 200.
  static Future<List<ChatChannelEvent>> fetchEvents(
    int channelId, {
    int after = 0,
  }) async {
    final response = await instance.authenticatedGet(
      _uri(channelId, '/events', {'after': '$after'}),
    );
    _check(response, 'fetch events of channel $channelId');
    return [
      for (final e in _json(response)['events'] as List? ?? const [])
        ChatChannelEvent.fromJson(e as Map<String, dynamic>),
    ];
  }

  /// Stores this account's [signature] on its own event [eventId].
  static Future<void> signEvent(
    int channelId,
    int eventId,
    Uint8List signature,
  ) async {
    final response = await instance.authenticatedPut(
      _uri(channelId, '/events/$eventId/signature'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'signature': base64Encode(signature)}),
    );
    _check(response, 'sign event $eventId of channel $channelId');
  }

  static Uri _uri(int channelId, String suffix, [Map<String, String>? query]) =>
      apiBaseUri
          .resolve('/api/v0/chat/channels/$channelId$suffix')
          .replace(queryParameters: query);

  static Map<String, dynamic> _json(http.Response response) =>
      jsonDecode(response.body) as Map<String, dynamic>;

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
