import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/chat_keys_controller.dart';
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/chat_channel_keys_service.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/events_service.dart';
import 'package:sodium/sodium_sumo.dart';

/// Opens, shares and rotates channel keys for the signed-in account (#2417).
///
/// A channel's messages are encrypted under a key the Quark never sees. Each
/// version of it reaches a member as a grant: the key sealed to their X25519
/// key and signed by the member who shared it. This controller does the
/// client's half:
///
/// - [ensureKeys] fetches this account's grants, rejects any whose signature
///   fails, and keeps the opened keys in memory by version. When the channel
///   has no key yet (a new channel, or `general` on a new Quark) or needs
///   rotating because someone left, it creates the next version; and when it
///   holds a version other members lack, it seals and signs grants for them.
/// - Until a member shares the current version, the channel is [isWaiting]:
///   "Waiting for a member to share the key", not an error.
/// - [start] follows `chat_key_needed`, so a member added through a group
///   gets their grants from whoever is online, and `chat_key_granted`, so a
///   waiting channel opens as soon as its grant lands.
///
/// Messages (#2418) call [keyFor] with the version a message names and
/// encrypt new ones under [currentVersion]. Nothing is cached on disk: a
/// restart fetches the grants again.
class ChatChannelKeysController extends ChangeNotifier {
  /// Builds a controller. Every collaborator has a real default; tests pass
  /// fakes.
  ChatChannelKeysController({
    ChatIdentity? Function()? identity,
    ChatCrypto? Function()? crypto,
    int? Function()? userId,
    Future<ChatChannelKeys> Function(int channelId)? fetchKeys,
    Future<ChatChannelEvent?> Function(
      int channelId,
      int version,
      Uint8List sealedKey,
      Uint8List signature,
    )?
    createVersion,
    Future<ChatPendingGrants> Function(int channelId)? fetchPending,
    Future<void> Function(int channelId, List<ChatGrantUpload> grants)?
    uploadGrants,
    Future<void> Function(int channelId, int eventId, Uint8List signature)?
    signEvent,
  }) : _identity = identity ?? (() => ChatKeysController.instance.identity),
       _crypto = crypto ?? (() => ChatKeysController.instance.crypto),
       _userId = userId ?? (() => AppSettings.instance.userId.value),
       _fetchKeys = fetchKeys ?? ChatChannelKeysService.fetchKeys,
       _createVersion = createVersion ?? ChatChannelKeysService.createVersion,
       _fetchPending = fetchPending ?? ChatChannelKeysService.fetchPending,
       _uploadGrants = uploadGrants ?? ChatChannelKeysService.uploadGrants,
       _signEvent = signEvent ?? ChatChannelKeysService.signEvent;

  /// The app's controller.
  static final ChatChannelKeysController instance = ChatChannelKeysController();

  /// The most grants sent in one upload, the Quark's cap.
  static const maxGrantsPerUpload = 256;

  final ChatIdentity? Function() _identity;
  final ChatCrypto? Function() _crypto;
  final int? Function() _userId;
  final Future<ChatChannelKeys> Function(int channelId) _fetchKeys;
  final Future<ChatChannelEvent?> Function(
    int channelId,
    int version,
    Uint8List sealedKey,
    Uint8List signature,
  )
  _createVersion;
  final Future<ChatPendingGrants> Function(int channelId) _fetchPending;
  final Future<void> Function(int channelId, List<ChatGrantUpload> grants)
  _uploadGrants;
  final Future<void> Function(int channelId, int eventId, Uint8List signature)
  _signEvent;

  final Map<int, Map<int, SecureKey>> _keys = {};
  final Map<int, int> _current = {};
  final Set<int> _waiting = {};
  final Map<int, Future<bool>> _running = {};
  StreamSubscription<FileEvent>? _events;
  Listenable? _lockSignal;

  /// The opened key for [version] of [channelId], or null when this account
  /// has no verified grant of it. Owned here: don't dispose it.
  SecureKey? keyFor(int channelId, int version) => _keys[channelId]?[version];

  /// The channel's newest key version as of the last [ensureKeys], 0 when
  /// unknown or none exists.
  int currentVersion(int channelId) => _current[channelId] ?? 0;

  /// Whether the last [ensureKeys] found no grant of the current version yet.
  bool isWaiting(int channelId) => _waiting.contains(channelId);

  /// Brings [channelId]'s keys up to date and returns whether it is waiting
  /// for a member to share the current version.
  ///
  /// Calls for the same channel share one run. Chat must be unlocked
  /// (`ChatKeysController.isUnlocked`); a locked one throws [StateError].
  Future<bool> ensureKeys(int channelId) =>
      _running[channelId] ??= _ensure(channelId).whenComplete(() {
        // A block body: returning the removed future would make this wait on
        // itself.
        _running.remove(channelId);
      });

  /// Follows the events that ask this client to act, and forgets every key
  /// when chat locks. Call once at startup; the arguments are for tests.
  void start({Stream<FileEvent>? events, Listenable? lockSignal}) {
    _events ??= (events ?? EventsService.instance.events).listen(_onEvent);
    _lockSignal ??= (lockSignal ?? ChatKeysController.instance)
      ..addListener(_onLockChanged);
  }

  /// Signs [event], which this account made: the membership screen calls it
  /// with the event a member change returned. Check [event]'s payload says
  /// what you did before signing it.
  Future<void> signEvent(ChatChannelEvent event) async {
    final (identity, crypto, me) = _unlocked();
    if (event.actorId != me) {
      throw ArgumentError('event ${event.id} is not this account\'s');
    }
    await _signEvent(
      event.channelId,
      event.id,
      crypto.sign(_eventMessage(crypto, event), identity),
    );
  }

  /// Signs [event] when it records giving account [userId] or group
  /// [groupId] [level] (removing its row when [level] is null), which is what
  /// this account just asked for. Anything else, or a failure to sign, is
  /// logged and left unsigned, so every member sees the line as unverified;
  /// the change itself already happened.
  Future<void> signMemberChange(
    ChatChannelEvent? event, {
    int? userId,
    int? groupId,
    String? level,
  }) async {
    if (event == null) return;
    if (!event.describesMemberChange(
      userId: userId,
      groupId: groupId,
      level: level,
    )) {
      debugPrint('chat: event ${event.id} does not match the change made');
      return;
    }
    try {
      await signEvent(event);
    } catch (e) {
      debugPrint('chat: could not sign event ${event.id}: $e');
    }
  }

  /// Whether [event] carries a valid signature by its actor. An unsigned or
  /// failing one is shown as unverified.
  bool verifyEvent(ChatChannelEvent event) {
    final crypto = _crypto();
    final signature = event.signature;
    final signKey = event.signerSignKey;
    if (crypto == null || signature == null || signKey == null) return false;
    return crypto.verify(_eventMessage(crypto, event), signature, signKey);
  }

  /// Forgets every opened key.
  void forget() {
    for (final versions in _keys.values) {
      for (final key in versions.values) {
        key.dispose();
      }
    }
    _keys.clear();
    _current.clear();
    _waiting.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _events?.cancel();
    _lockSignal?.removeListener(_onLockChanged);
    forget();
    super.dispose();
  }

  Future<bool> _ensure(int channelId) async {
    final (identity, crypto, me) = _unlocked();
    var state = await _fetchKeys(channelId);
    _open(channelId, state.grants, identity, crypto, me);
    var current = state.currentVersion;
    if (current == 0 || state.rotationNeeded) {
      if (await _create(channelId, current + 1, identity, crypto, me)) {
        current++;
      } else {
        // Another member got there first; their grant comes to us.
        state = await _fetchKeys(channelId);
        _open(channelId, state.grants, identity, crypto, me);
        current = state.currentVersion;
      }
    }
    if (_keys[channelId]?.isNotEmpty ?? false) {
      await _fillPending(channelId, identity, crypto);
    }
    _current[channelId] = current;
    final waiting = keyFor(channelId, current) == null;
    if (waiting) {
      _waiting.add(channelId);
    } else {
      _waiting.remove(channelId);
    }
    notifyListeners();
    return waiting;
  }

  /// Verifies and opens this account's grants, skipping any already open or
  /// failing.
  void _open(
    int channelId,
    List<ChatKeyGrant> grants,
    ChatIdentity identity,
    ChatCrypto crypto,
    int me,
  ) {
    final versions = _keys.putIfAbsent(channelId, () => {});
    for (final grant in grants) {
      if (versions.containsKey(grant.version)) continue;
      final message = crypto.grantMessage(
        channelId: channelId,
        version: grant.version,
        userId: me,
        sealedKey: grant.sealedKey,
      );
      if (grant.userId != me ||
          !crypto.verify(message, grant.signature, grant.granterSignKey)) {
        debugPrint(
          '[chat_channel_keys_controller.dart] rejected grant of version '
          '${grant.version} in channel $channelId: bad signature',
        );
        continue;
      }
      try {
        versions[grant.version] = crypto.channelKeyFromBytes(
          crypto.openSealed(grant.sealedKey, identity),
        );
      } on Object catch (e) {
        debugPrint(
          '[chat_channel_keys_controller.dart] grant of version '
          '${grant.version} in channel $channelId won\'t open: $e',
        );
      }
    }
  }

  /// Creates [version] with our own grant, and signs its event. False when
  /// another member created it first.
  Future<bool> _create(
    int channelId,
    int version,
    ChatIdentity identity,
    ChatCrypto crypto,
    int me,
  ) async {
    final key = crypto.newChannelKey();
    final sealed = crypto.seal(key.extractBytes(), identity.box.publicKey);
    final signature = crypto.sign(
      crypto.grantMessage(
        channelId: channelId,
        version: version,
        userId: me,
        sealedKey: sealed,
      ),
      identity,
    );
    final ChatChannelEvent? event;
    try {
      event = await _createVersion(channelId, version, sealed, signature);
    } catch (_) {
      key.dispose();
      rethrow;
    }
    if (event == null) {
      key.dispose();
      return false;
    }
    _keys.putIfAbsent(channelId, () => {})[version]?.dispose();
    _keys[channelId]![version] = key;
    // Sign only what we just did.
    if (event.kind == ChatChannelEvent.keyCreated &&
        event.actorId == me &&
        event.data['version'] == version) {
      await _signEvent(
        channelId,
        event.id,
        crypto.sign(_eventMessage(crypto, event), identity),
      );
    }
    return true;
  }

  /// Seals and signs every version we hold for the members who lack it.
  Future<void> _fillPending(
    int channelId,
    ChatIdentity identity,
    ChatCrypto crypto,
  ) async {
    final pending = await _fetchPending(channelId);
    final uploads = <ChatGrantUpload>[];
    for (final p in pending.pending) {
      final key = keyFor(channelId, p.version);
      if (key == null) continue;
      final sealed = crypto.seal(key.extractBytes(), p.boxPublicKey);
      uploads.add(
        ChatGrantUpload(
          version: p.version,
          userId: p.userId,
          sealedKey: sealed,
          signature: crypto.sign(
            crypto.grantMessage(
              channelId: channelId,
              version: p.version,
              userId: p.userId,
              sealedKey: sealed,
            ),
            identity,
          ),
        ),
      );
    }
    for (var i = 0; i < uploads.length; i += maxGrantsPerUpload) {
      final end = i + maxGrantsPerUpload;
      await _uploadGrants(
        channelId,
        uploads.sublist(i, end < uploads.length ? end : uploads.length),
      );
    }
  }

  Uint8List _eventMessage(ChatCrypto crypto, ChatChannelEvent event) =>
      crypto.eventMessage(
        channelId: event.channelId,
        eventId: event.id,
        actorId: event.actorId,
        kind: event.kind,
        payload: event.payload,
      );

  (ChatIdentity, ChatCrypto, int) _unlocked() {
    final identity = _identity();
    final crypto = _crypto();
    final me = _userId();
    if (identity == null || crypto == null || me == null) {
      throw StateError('chat is locked');
    }
    return (identity, crypto, me);
  }

  void _onEvent(FileEvent event) {
    if (event.kind != 'chat_key_needed' && event.kind != 'chat_key_granted') {
      return;
    }
    final data = event.data;
    final channelId = data is Map ? (data['channelId'] as num?)?.toInt() : null;
    if (channelId == null || _identity() == null) return;
    ensureKeys(channelId).catchError((Object e) {
      // An admin hears every channel's events, including ones it isn't in.
      debugPrint(
        '[chat_channel_keys_controller.dart] channel $channelId keys: $e',
      );
      return true;
    });
  }

  void _onLockChanged() {
    if (_identity() == null && _keys.isNotEmpty) forget();
  }
}
