import 'dart:convert';
import 'dart:typed_data';

/// A channel's key versions and the signed-in account's grants of them, from
/// `GET /api/v0/chat/channels/:id/keys` (#2417).
class ChatChannelKeys {
  /// Builds the state explicitly; tests use it.
  const ChatChannelKeys({
    required this.currentVersion,
    required this.versions,
    required this.grants,
    required this.rotationNeeded,
  });

  /// The newest version, 0 before any exists.
  final int currentVersion;

  /// Every version, oldest first.
  final List<int> versions;

  /// This account's grants, one per version it has been given.
  final List<ChatKeyGrant> grants;

  /// Someone outside the channel holds [currentVersion], so the next member
  /// online creates a new one.
  final bool rotationNeeded;

  /// Reads the route's JSON.
  factory ChatChannelKeys.fromJson(Map<String, dynamic> json) =>
      ChatChannelKeys(
        currentVersion: (json['currentVersion'] as num).toInt(),
        versions: [
          for (final v in json['versions'] as List? ?? const [])
            ((v as Map)['version'] as num).toInt(),
        ],
        grants: [
          for (final g in json['grants'] as List? ?? const [])
            ChatKeyGrant.fromJson(g as Map<String, dynamic>),
        ],
        rotationNeeded: json['rotationNeeded'] as bool? ?? false,
      );
}

/// One version of a channel key sealed to one member and signed by whoever
/// granted it.
class ChatKeyGrant {
  /// Builds a grant explicitly; tests use it.
  const ChatKeyGrant({
    required this.version,
    required this.userId,
    required this.sealedKey,
    required this.grantedBy,
    required this.granterSignKey,
    required this.signature,
  });

  /// The key version.
  final int version;

  /// The recipient.
  final int userId;

  /// `crypto_box_seal` of the channel key to the recipient's X25519 key.
  final Uint8List sealedKey;

  /// The granter, 0 once that account is deleted.
  final int grantedBy;

  /// The granter's published Ed25519 key when the grant was uploaded.
  final Uint8List granterSignKey;

  /// The granter's signature over `ChatCrypto.grantMessage`.
  final Uint8List signature;

  /// Reads one grant.
  factory ChatKeyGrant.fromJson(Map<String, dynamic> json) => ChatKeyGrant(
    version: (json['version'] as num).toInt(),
    userId: (json['userId'] as num).toInt(),
    sealedKey: base64Decode(json['sealedKey'] as String),
    grantedBy: (json['grantedBy'] as num?)?.toInt() ?? 0,
    granterSignKey: base64Decode(json['granterSignKey'] as String),
    signature: base64Decode(json['signature'] as String),
  );
}

/// What `GET /api/v0/chat/channels/:id/keys/pending` answers: the grants this
/// account holds the key to fill.
class ChatPendingGrants {
  /// Builds the answer explicitly; tests use it.
  const ChatPendingGrants({
    required this.pending,
    required this.currentVersion,
    required this.rotationNeeded,
  });

  /// Members missing a version this account holds.
  final List<ChatPendingGrant> pending;

  /// The newest version, 0 before any.
  final int currentVersion;

  /// As [ChatChannelKeys.rotationNeeded].
  final bool rotationNeeded;

  /// Reads the route's JSON.
  factory ChatPendingGrants.fromJson(Map<String, dynamic> json) =>
      ChatPendingGrants(
        pending: [
          for (final p in json['pending'] as List? ?? const [])
            ChatPendingGrant.fromJson(p as Map<String, dynamic>),
        ],
        currentVersion: (json['currentVersion'] as num).toInt(),
        rotationNeeded: json['rotationNeeded'] as bool? ?? false,
      );
}

/// A member missing one version of a channel key.
class ChatPendingGrant {
  /// Builds one explicitly; tests use it.
  const ChatPendingGrant({
    required this.version,
    required this.userId,
    required this.boxPublicKey,
  });

  /// The version they lack.
  final int version;

  /// The member.
  final int userId;

  /// Their X25519 key, to seal the channel key to.
  final Uint8List boxPublicKey;

  /// Reads one entry.
  factory ChatPendingGrant.fromJson(Map<String, dynamic> json) =>
      ChatPendingGrant(
        version: (json['version'] as num).toInt(),
        userId: (json['userId'] as num).toInt(),
        boxPublicKey: base64Decode(json['boxPublicKey'] as String),
      );
}

/// A grant this client sealed and signed, for `POST .../keys/grants`.
class ChatGrantUpload {
  /// Pairs the recipient with the sealed key and signature.
  const ChatGrantUpload({
    required this.version,
    required this.userId,
    required this.sealedKey,
    required this.signature,
  });

  /// The key version.
  final int version;

  /// The recipient.
  final int userId;

  /// The key sealed to the recipient.
  final Uint8List sealedKey;

  /// This account's signature over `ChatCrypto.grantMessage`.
  final Uint8List signature;

  /// The upload's JSON.
  Map<String, dynamic> toJson() => {
    'version': version,
    'userId': userId,
    'sealedKey': base64Encode(sealedKey),
    'signature': base64Encode(signature),
  };
}

/// A membership or key change in a channel, shown as a system line (#2417).
///
/// The Quark writes [payload]; the actor's client signs it afterward. One
/// without a [signature] is shown as unverified.
class ChatChannelEvent {
  /// Builds an event explicitly; tests use it.
  const ChatChannelEvent({
    required this.id,
    required this.channelId,
    required this.kind,
    required this.actorId,
    required this.payload,
    required this.createdAt,
    this.signature,
    this.signerSignKey,
  });

  /// The kind the Quark records when an account or group gets a level.
  static const memberSet = 'member_set';

  /// The kind for a row removed, leaving included (actor is the member).
  static const memberRemoved = 'member_removed';

  /// The kind for a new key version.
  static const keyCreated = 'key_created';

  /// Increasing within the Quark.
  final int id;

  /// The channel it happened in.
  final int channelId;

  /// [memberSet], [memberRemoved] or [keyCreated].
  final String kind;

  /// Who did it, 0 once that account is deleted.
  final int actorId;

  /// The JSON the signature covers, byte for byte: `{"userId"|"groupId",
  /// "name", "level"}` for a member change, `{"version"}` for a key.
  final String payload;

  /// When the Quark recorded it.
  final DateTime createdAt;

  /// The actor's signature over `ChatCrypto.eventMessage`, null until signed.
  final Uint8List? signature;

  /// The actor's published Ed25519 key when they signed.
  final Uint8List? signerSignKey;

  /// [payload], decoded.
  Map<String, dynamic> get data => jsonDecode(payload) as Map<String, dynamic>;

  /// Whether this records giving account [userId] or group [groupId]
  /// [level], or removing its row when [level] is null: what a client checks
  /// before signing the event a member change returned.
  bool describesMemberChange({int? userId, int? groupId, String? level}) {
    if (kind != (level == null ? memberRemoved : memberSet)) return false;
    final Map<String, dynamic> d;
    try {
      d = data;
    } on Object {
      return false;
    }
    return (d['userId'] as num?)?.toInt() == userId &&
        (d['groupId'] as num?)?.toInt() == groupId &&
        d['level'] == level;
  }

  /// Reads one event.
  factory ChatChannelEvent.fromJson(Map<String, dynamic> json) {
    Uint8List? bytes(String key) {
      final value = json[key] as String?;
      return value == null ? null : base64Decode(value);
    }

    return ChatChannelEvent(
      id: (json['id'] as num).toInt(),
      channelId: (json['channelId'] as num).toInt(),
      kind: json['kind'] as String,
      actorId: (json['actorId'] as num?)?.toInt() ?? 0,
      payload: json['payload'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      signature: bytes('signature'),
      signerSignKey: bytes('signerSignKey'),
    );
  }
}
