import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';

/// The channel key and event routes under `/api/v0/chat/channels/:id` (#2417):
/// key versions and this account's grants, the grants it can fill, uploading
/// them, rejecting its own, creating a version, and the channel's signed system
/// events.
///
/// Everything here is sealed keys, signatures and public keys;
/// `ChatChannelKeysController` does the crypto. Regenerating a version is
/// the admin route for a channel stuck on an offline holder (#3455).
class ChatChannelKeysService with AuthenticatedService {
  ChatChannelKeysService._();

  /// The one instance, for the [AuthenticatedService] helpers.
  static final ChatChannelKeysService instance = ChatChannelKeysService._();

  /// Channel [channelId]'s key versions and this account's grants.
  ///
  /// api: GET /api/v0/chat/channels/{id}/keys
  static Future<ChatChannelKeys> fetchKeys(int channelId) async {
    final response = await instance.authenticatedGet(_uri(channelId, '/keys'));
    throwUnlessOk(response, 'fetch keys of channel $channelId');
    return ChatChannelKeys.fromJson(_json(response));
  }

  /// Creates [version] with this account's own grant of it, and returns the
  /// `key_created` event to sign; null when another member created it first.
  ///
  /// api: POST /api/v0/chat/channels/{id}/keys
  static Future<ChatChannelEvent?> createVersion(
    int channelId,
    int version,
    Uint8List sealedKey,
    Uint8List signature,
  ) => _postVersion(
    channelId,
    '/keys',
    version,
    sealedKey,
    signature,
    'create key $version of channel $channelId',
  );

  /// Creates [version] even when the key does not need rotating. Admin only
  /// (#3455). Null when another member created that version first.
  ///
  /// api: POST /api/v0/chat/channels/{id}/keys/regenerate
  static Future<ChatChannelEvent?> regenerateVersion(
    int channelId,
    int version,
    Uint8List sealedKey,
    Uint8List signature,
  ) => _postVersion(
    channelId,
    '/keys/regenerate',
    version,
    sealedKey,
    signature,
    'regenerate key $version of channel $channelId',
  );

  /// api: none
  static Future<ChatChannelEvent?> _postVersion(
    int channelId,
    String suffix,
    int version,
    Uint8List sealedKey,
    Uint8List signature,
    String action,
  ) async {
    final response = await instance.authenticatedPost(
      _uri(channelId, suffix),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'version': version,
        'sealedKey': base64Encode(sealedKey),
        'signature': base64Encode(signature),
      }),
    );
    if (response.statusCode == 409) return null;
    throwUnlessOk(response, action);
    return ChatChannelEvent.fromJson(
      _json(response)['event'] as Map<String, dynamic>,
    );
  }

  /// The grants this account holds the key to fill.
  ///
  /// api: GET /api/v0/chat/channels/{id}/keys/pending
  static Future<ChatPendingGrants> fetchPending(int channelId) async {
    final response = await instance.authenticatedGet(
      _uri(channelId, '/keys/pending'),
    );
    throwUnlessOk(response, 'fetch pending grants of channel $channelId');
    return ChatPendingGrants.fromJson(_json(response));
  }

  /// Uploads [grants]. The Quark keeps the first grant per member and
  /// version, so a duplicate is harmless.
  ///
  /// api: POST /api/v0/chat/channels/{id}/keys/grants
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
    throwUnlessOk(response, 'upload grants of channel $channelId');
  }

  /// Deletes this account's own grant of [version], one it couldn't open or
  /// verify, so another member refills it (#2486).
  ///
  /// api: DELETE /api/v0/chat/channels/{id}/keys/grants/{version}
  static Future<void> rejectGrant(int channelId, int version) async {
    final response = await instance.authenticatedDelete(
      _uri(channelId, '/keys/grants/$version'),
    );
    throwUnlessOk(response, 'reject grant $version of channel $channelId');
  }

  /// The channel's events after [after], oldest first, at most 200.
  ///
  /// api: GET /api/v0/chat/channels/{id}/events
  static Future<List<ChatChannelEvent>> fetchEvents(
    int channelId, {
    int after = 0,
  }) async {
    final response = await instance.authenticatedGet(
      _uri(channelId, '/events', {'after': '$after'}),
    );
    throwUnlessOk(response, 'fetch events of channel $channelId');
    return [
      for (final e in _json(response)['events'] as List? ?? const [])
        ChatChannelEvent.fromJson(e as Map<String, dynamic>),
    ];
  }

  /// Stores this account's [signature] on its own event [eventId].
  ///
  /// api: PUT /api/v0/chat/channels/{id}/events/{eventId}/signature
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
    throwUnlessOk(response, 'sign event $eventId of channel $channelId');
  }

  /// api: none
  static Uri _uri(int channelId, String suffix, [Map<String, String>? query]) =>
      apiBaseUri
          .resolve('/api/v0/chat/channels/$channelId$suffix')
          .replace(queryParameters: query);

  static Map<String, dynamic> _json(http.Response response) =>
      jsonDecode(response.body) as Map<String, dynamic>;
}
