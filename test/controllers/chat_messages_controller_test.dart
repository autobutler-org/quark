import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/chat_channel_keys_controller.dart';
import 'package:quark/controllers/chat_controller.dart';
import 'package:quark/controllers/chat_messages_controller.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/models/chat_message.dart';
import 'package:quark/models/chat_poll.dart';
import 'package:quark/services/chat_attachment_message.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/chat_config.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:sodium/sodium_sumo.dart';

const _channel = 7;
final _epoch = DateTime.utc(2026, 9, 1);

/// The keys one client holds, set by hand.
class _FakeKeys extends ChatChannelKeysController {
  final Map<int, SecureKey> held = {};
  int current = 1;

  /// Makes [version] available, as a grant landing would.
  void grant(int version, SecureKey key) {
    held[version] = key;
    notifyListeners();
  }

  /// Forgets every key, as locking chat does.
  void forgetAll() {
    held.clear();
    notifyListeners();
  }

  @override
  Future<bool> ensureKeys(int channelId) async => held[current] == null;

  @override
  SecureKey? keyFor(int channelId, int version) =>
      channelId == _channel ? held[version] : null;

  @override
  int currentVersion(int channelId) => current;

  @override
  bool verifyEvent(ChatChannelEvent event) => event.signature != null;
}

/// A Quark storing messages and events the way the real one does. [live]
/// is its events socket; set [drop] to lose what it would send.
class _FakeQuark {
  final List<ChatMessage> messages = [];
  final List<ChatChannelEvent> events = [];
  final Map<int, List<ChatReaction>> reactions = {};

  /// Each poll's settings and state, by message id.
  final Map<int, ChatPoll> polls = {};

  /// Each poll's answers by the account that gave them.
  final Map<int, Map<int, ChatPollResponse>> answers = {};

  /// Who hears an event on [live]; everyone when unset.
  final audience = Expando<Set<int>>();
  final live = StreamController<FileEvent>.broadcast();
  final reconnects = StreamController<void>.broadcast();
  bool drop = false;

  /// Stores the next post and then throws, as a response lost on the way
  /// back does.
  bool loseResponse = false;

  /// What each client message id was stored as, the way the Quark answers a
  /// repeated one (#3531).
  final Map<String, ChatMessage> byClientId = {};

  /// Attachment ids uploaded with [putAttachment], in order.
  final List<String> uploadedAttachmentIds = [];

  /// The ids on the last post, when it named any.
  List<String>? lastAttachmentIds;

  /// How many times an attachment body was downloaded.
  var attachmentDownloads = 0;

  /// Ciphertext uploaded for an attachment id, so a later download can open it.
  final Map<String, List<int>> attachmentBodies = {};

  /// How many times a client said it was typing.
  var typings = 0;

  /// How many times a client read a side conversation's replies.
  var replyFetches = 0;

  int _nextId = 1;

  ChatMessagesController client(
    _FakeKeys keys,
    ChatCrypto crypto, {
    int userId = 2,
    bool selfFromKeys = false,
    int? rootId,
    SaveChatAttachmentFn? saveAttachmentFile,
    UploadChatAttachmentFn? uploadAttachmentFile,
    Future<Uint8List?> Function(String name, Uint8List bytes)?
    renderVideoThumbnail,
  }) => ChatMessagesController(
    channelId: _channel,
    rootId: rootId,
    keys: keys,
    crypto: () => crypto,
    fetchMessages: (channelId, {before, after, limit}) async {
      final n = limit ?? 50;
      final inChannel = messages.where(
        (m) => m.channelId == channelId && m.rootId == null,
      );
      ChatMessage withReactions(ChatMessage m) => m.copyWith(
        reactions: reactions[m.id] ?? const [],
        poll: polls[m.id]?.copyWith(answers: visibleAnswers(m.id, userId)),
      );
      if (after != null) {
        return inChannel
            .where((m) => m.id > after)
            .take(n)
            .map(withReactions)
            .toList();
      }
      final older = inChannel
          .where((m) => before == null || m.id < before)
          .map(withReactions)
          .toList();
      return older.sublist(older.length > n ? older.length - n : 0);
    },
    fetchReplies: (rootId, {before, after, limit}) async {
      replyFetches++;
      final replies = messages.where((m) => m.rootId == rootId);
      return [
        for (final m in replies)
          if ((after == null || m.id > after) &&
              (before == null || m.id < before))
            m,
      ];
    },
    postMessage:
        (
          channelId,
          keyVersion,
          ciphertext, {
          clientMessageId,
          attachmentIds,
          poll,
          rootId,
        }) async {
          lastAttachmentIds = attachmentIds;
          final stored = byClientId[clientMessageId];
          if (stored != null) return stored;
          final message = post(
            channelId,
            keyVersion,
            ciphertext,
            poll: poll,
            rootId: rootId,
          );
          if (clientMessageId != null) byClientId[clientMessageId] = message;
          if (loseResponse) {
            loseResponse = false;
            throw Exception('timed out');
          }
          return message;
        },
    sendTyping: (channelId) async {
      typings++;
      _emit('chat_typing', {
        'channelId': channelId,
        'userId': userId,
      }, hears: {2, 3}..remove(userId));
    },
    editMessage: (id, keyVersion, ciphertext) async =>
        edit(id, keyVersion, ciphertext),
    deleteMessage: (id) async {
      final i = messages.indexWhere((m) => m.id == id);
      messages[i] = messages[i].tombstone(_epoch);
      reactions.remove(id);
      return messages[i];
    },
    addReaction: (messageId, keyVersion, ciphertext) async =>
        react(messageId, userId, keyVersion, ciphertext),
    deleteReaction: (id) async => removeReaction(id),
    answerPoll: (messageId, keyVersion, ciphertext) async =>
        answer(messageId, userId, keyVersion, ciphertext),
    fetchPollAnswers: (messageId) async => visibleAnswers(messageId, userId),
    closePoll: (messageId) async => close(messageId),
    putAttachment: (channelId, id, body) async {
      uploadedAttachmentIds.add(id);
      final bytes = body is List<int> ? List<int>.from(body) : const <int>[];
      attachmentBodies[id] = bytes;
      return bytes.length;
    },
    getAttachment: (channelId, id, {sink}) async {
      attachmentDownloads++;
      return Stream<List<int>>.value(attachmentBodies[id] ?? const <int>[]);
    },
    currentUserId: selfFromKeys ? null : () => userId,
    fetchEvents: (channelId, {after = 0}) async =>
        events.where((e) => e.id > after).toList(),
    events: live.stream.where((e) => audience[e]?.contains(userId) ?? true),
    reconnects: reconnects.stream,
    saveAttachmentFile: saveAttachmentFile,
    uploadAttachmentFile: uploadAttachmentFile,
    renderVideoThumbnail: renderVideoThumbnail,
  );

  ChatReaction react(
    int messageId,
    int userId,
    int keyVersion,
    Uint8List ciphertext,
  ) {
    final reaction = ChatReaction(
      id: _nextId++,
      messageId: messageId,
      userId: userId,
      keyVersion: keyVersion,
      ciphertext: ciphertext,
      createdAt: _epoch,
    );
    (reactions[messageId] ??= []).add(reaction);
    _reactionChanged(reaction.messageId, reaction.id, {
      'id': reaction.id,
      'messageId': messageId,
      'userId': userId,
      'keyVersion': keyVersion,
      'ciphertext': base64Encode(ciphertext),
      'createdAt': _epoch.toIso8601String(),
    });
    return reaction;
  }

  void removeReaction(int id) {
    for (final MapEntry(key: messageId, value: list) in reactions.entries) {
      if (list.any((r) => r.id == id)) {
        list.removeWhere((r) => r.id == id);
        _reactionChanged(messageId, id, null);
        return;
      }
    }
  }

  void _reactionChanged(int messageId, int id, Map<String, Object>? row) {
    if (drop) return;
    live.add(
      FileEvent(
        kind: 'chat_reaction_changed',
        path: '',
        data: jsonDecode(
          jsonEncode({
            'channelId': _channel,
            'messageId': messageId,
            'reactionId': id,
            'reaction': ?row,
          }),
        ),
      ),
    );
  }

  /// [row] as account [viewer] is served it: no account on an anonymous
  /// poll, and marked when it is the viewer's own.
  ChatPollResponse served(ChatPollResponse row, int viewer) => ChatPollResponse(
    id: row.id,
    messageId: row.messageId,
    keyVersion: row.keyVersion,
    ciphertext: row.ciphertext,
    userId: polls[row.messageId]!.anonymous ? null : row.userId,
    mine: row.userId == viewer,
  );

  /// The answers to poll [messageId] that account [viewer] may see: only
  /// its own while a results-after-close poll is open and it isn't the
  /// author.
  List<ChatPollResponse> visibleAnswers(int messageId, int viewer) {
    final poll = polls[messageId]!;
    final ownOnly = poll.resultsAfterClose && !poll.closed && viewer != 2;
    return [
      for (final row in answers[messageId]?.values ?? <ChatPollResponse>[])
        if (!ownOnly || row.userId == viewer) served(row, viewer),
    ];
  }

  ChatPollResponse answer(
    int messageId,
    int userId,
    int keyVersion,
    Uint8List ciphertext,
  ) {
    final poll = polls[messageId];
    if (poll == null) throw const ApiException(404);
    expect(ciphertext, hasLength(4136));
    final held = answers[messageId]?[userId];
    if (poll.closed || (held != null && !poll.allowChange)) {
      throw const ApiException(409);
    }
    final row = ChatPollResponse(
      id: held?.id ?? _nextId++,
      messageId: messageId,
      userId: userId,
      keyVersion: keyVersion,
      ciphertext: ciphertext,
    );
    (answers[messageId] ??= {})[userId] = row;
    // An anonymous poll names the poll and not the answer. The server holds
    // the author's copy of a results-after-close note until a clock boundary;
    // this delivers it now, and the client only reads the answers again.
    if (poll.anonymous) {
      _emit('chat_poll_answers_changed', {
        'channelId': _channel,
        'messageId': messageId,
      }, hears: poll.resultsAfterClose ? {2, userId} : null);
      return served(row, userId);
    }
    final event = served(row, 0);
    _emit('chat_poll_answer_changed', {
      'channelId': _channel,
      'messageId': messageId,
      'answer': {
        'id': event.id,
        'messageId': messageId,
        'userId': ?event.userId,
        'mine': false,
        'keyVersion': keyVersion,
        'ciphertext': base64Encode(ciphertext),
      },
    }, hears: poll.resultsAfterClose ? {2, userId} : null);
    return served(row, userId);
  }

  ChatPoll close(int messageId) {
    final poll = polls[messageId] = polls[messageId]!.copyWith(closed: true);
    _emit('chat_poll_closed', {'channelId': _channel, 'messageId': messageId});
    return poll;
  }

  void _emit(String kind, Map<String, Object> data, {Set<int>? hears}) {
    if (drop) return;
    final event = FileEvent(
      kind: kind,
      path: '',
      data: jsonDecode(jsonEncode(data)),
    );
    audience[event] = hears;
    live.add(event);
  }

  /// Replaces message [id]'s ciphertext as the Quark does: editedAt set,
  /// and the row without its reactions to every reader.
  ChatMessage edit(int id, int keyVersion, Uint8List ciphertext) {
    final i = messages.indexWhere((m) => m.id == id);
    final old = messages[i];
    final edited = messages[i] = ChatMessage(
      id: id,
      channelId: old.channelId,
      authorId: old.authorId,
      keyVersion: keyVersion,
      ciphertext: ciphertext,
      createdAt: old.createdAt,
      editedAt: _epoch.add(const Duration(days: 1)),
      rootId: old.rootId,
    );
    _emit('chat_message_edited', {
      'channelId': old.channelId,
      'messageId': id,
      'message': {
        'id': id,
        'channelId': old.channelId,
        'authorId': old.authorId,
        'keyVersion': keyVersion,
        'ciphertext': base64Encode(ciphertext),
        'createdAt': old.createdAt.toIso8601String(),
        'editedAt': edited.editedAt!.toIso8601String(),
        'rootId': ?old.rootId,
      },
    });
    return edited;
  }

  ChatMessage post(
    int channelId,
    int keyVersion,
    Uint8List ciphertext, {
    ChatPoll? poll,
    int? rootId,
    int authorId = 2,
  }) {
    final id = _nextId++;
    final message = ChatMessage(
      id: id,
      channelId: channelId,
      authorId: authorId,
      keyVersion: keyVersion,
      ciphertext: ciphertext,
      createdAt: _epoch.add(Duration(minutes: id * 2)),
      poll: poll,
      rootId: rootId,
    );
    if (poll != null) polls[id] = poll;
    messages.add(message);
    if (!drop) {
      live.add(
        FileEvent(
          kind: 'chat_message_created',
          path: '',
          data: jsonDecode(
            jsonEncode({
              'channelId': channelId,
              'messageId': id,
              'rootId': ?rootId,
              'message': {
                'id': id,
                'channelId': channelId,
                'authorId': authorId,
                'rootId': ?rootId,
                'keyVersion': keyVersion,
                'ciphertext': base64Encode(ciphertext),
                'createdAt': message.createdAt.toIso8601String(),
                'poll': ?poll?.settingsJson(),
              },
            }),
          ),
        ),
      );
    }
    if (rootId != null) {
      // The Quark tells the readers the root's new count too (#4346).
      final replies = messages.where((m) => m.rootId == rootId && !m.isDeleted);
      _emit('chat_branch_changed', {
        'channelId': channelId,
        'messageId': rootId,
        'replyCount': replies.length,
        'lastReplyAt': message.createdAt.toIso8601String(),
      });
    }
    return message;
  }
}

void main() {
  late ChatCrypto crypto;
  late _FakeQuark quark;

  setUpAll(() async => crypto = await ChatCrypto.load());
  setUp(() => quark = _FakeQuark());

  List<String?> texts(ChatMessagesController c) => [
    for (final e in c.entries)
      if (e is ChatTimelineMessage) e.text,
  ];

  // #3531: the Quark stored the first attempt but its response, and its
  // event, never arrived. The retry encrypts again under a fresh nonce, and
  // the client message id is what makes it one row on every device.
  test('a retry after a lost response is one message', () async {
    final key = crypto.newChannelKey();
    final alice = _FakeKeys()..grant(1, key);
    final sender = quark.client(alice, crypto);
    await sender.open();

    quark
      ..drop = true
      ..loseResponse = true;
    await expectLater(
      sender.send('hi', clientMessageId: 'send-1'),
      throwsException,
    );
    expect(texts(sender), isEmpty);
    await sender.send('hi', clientMessageId: 'send-1');

    expect(texts(sender), ['hi']);
    expect(quark.messages, hasLength(1));
    final reader = quark.client(_FakeKeys()..grant(1, key), crypto);
    await reader.open();
    expect(texts(reader), ['hi']);
    sender.dispose();
    reader.dispose();
  });

  test('send encrypts, and another member decrypts on open', () async {
    final key = crypto.newChannelKey();
    final alice = _FakeKeys()..grant(1, key);
    final sender = quark.client(alice, crypto);
    await sender.open();

    await sender.send('hello there');

    expect(texts(sender), ['hello there']);
    final stored = quark.messages.single;
    expect(
      utf8.decode(stored.ciphertext!, allowMalformed: true),
      isNot(contains('hello')),
    );

    final bob = _FakeKeys()
      ..grant(1, crypto.channelKeyFromBytes(key.extractBytes()));
    final reader = quark.client(bob, crypto);
    await reader.open();
    expect(texts(reader), ['hello there']);
  });

  test('an attachment posts with an empty caption and opens as text', () async {
    final key = crypto.newChannelKey();
    final alice = _FakeKeys()..grant(1, key);
    final sender = quark.client(alice, crypto);
    await sender.open();

    await sender.sendAttachment(
      name: 'cabin.png',
      mime: 'image/png',
      bytes: Uint8List.fromList(const [1, 2, 3, 4]),
      caption: 'look',
    );
    await sender.sendAttachment(
      name: 'notes.txt',
      mime: 'text/plain',
      bytes: Uint8List.fromList(const [9]),
    );

    final entries = [
      for (final e in sender.entries)
        if (e is ChatTimelineMessage) e,
    ];
    expect(entries, hasLength(2));
    expect(entries[0].text, 'look');
    expect(entries[0].attachments.single.name, 'cabin.png');
    expect(entries[0].attachments.single.size, 4);
    expect(entries[1].text, isEmpty);
    expect(entries[1].attachments.single.mime, 'text/plain');
    expect(quark.uploadedAttachmentIds, [
      entries[0].attachments.single.id,
      entries[1].attachments.single.id,
    ]);
    expect(quark.lastAttachmentIds, [entries[1].attachments.single.id]);

    final image = ChatController.itemFor(entries[0], (_) => 'Ada');
    expect(image.kind, ChatMessageKind.text);
    expect(image.body, 'look');
    expect(image.attachments.single.kind, ChatAttachmentKind.image);
    final file = ChatController.itemFor(entries[1], (_) => 'Ada');
    expect(file.attachments.single.kind, ChatAttachmentKind.file);

    final bob = _FakeKeys()
      ..grant(1, crypto.channelKeyFromBytes(key.extractBytes()));
    final reader = quark.client(bob, crypto);
    await reader.open();
    final got = [
      for (final e in reader.entries)
        if (e is ChatTimelineMessage) e,
    ];
    expect(got[0].text, 'look');
    expect(got[0].attachments.single.id, entries[0].attachments.single.id);
    expect(got[1].text, isEmpty);
    sender.dispose();
    reader.dispose();
  });

  test('a sent video keeps its preview frame', () async {
    final key = crypto.newChannelKey();
    final thumb = Uint8List.fromList(const [0xFF, 0xD8, 0xFF]);
    final plain = Uint8List.fromList(const [1, 2, 3, 4]);
    var renders = 0;
    final sender = quark.client(
      _FakeKeys()..grant(1, key),
      crypto,
      renderVideoThumbnail: (name, bytes) async {
        renders++;
        expect(name, 'hard-n.mp4');
        expect(bytes, plain);
        return thumb;
      },
    );
    await sender.open();
    await sender.sendAttachment(
      name: 'hard-n.mp4',
      mime: 'video/mp4',
      bytes: plain,
    );
    final id = [
      for (final entry in sender.entries)
        if (entry is ChatTimelineMessage) ...entry.attachments,
    ].single.id;

    expect(sender.thumbnailFor(id), thumb);
    expect(await sender.videoPreview(id), thumb);
    expect(renders, 1);
    expect(quark.attachmentDownloads, 0);
    sender.dispose();
  });

  test('a video with no stored frame is rendered once from the file', () async {
    final key = crypto.newChannelKey();
    final thumb = Uint8List.fromList(const [0xFF, 0xD8, 0xFF]);
    final plain = Uint8List.fromList(const [1, 2, 3, 4]);
    var renders = 0;
    final sender = quark.client(
      _FakeKeys()..grant(1, key),
      crypto,
      renderVideoThumbnail: (name, bytes) async {
        renders++;
        return renders == 1 ? null : thumb;
      },
    );
    await sender.open();
    await sender.sendAttachment(
      name: 'hard-n.mp4',
      mime: 'video/mp4',
      bytes: plain,
    );
    final id = [
      for (final entry in sender.entries)
        if (entry is ChatTimelineMessage) ...entry.attachments,
    ].single.id;

    expect(sender.thumbnailFor(id), isNull);
    expect(await sender.videoPreview(id), thumb);
    expect(await sender.videoPreview(id), thumb);
    expect(renders, 2);
    expect(quark.attachmentDownloads, 1);
    sender.dispose();
  });

  test('saving an attachment to a folder uploads its name there', () async {
    final key = crypto.newChannelKey();
    final uploads = <({String folder, String name, List<int> bytes})>[];
    final sender = quark.client(
      _FakeKeys()..grant(1, key),
      crypto,
      uploadAttachmentFile:
          ({required plaintext, required folder, required fileName}) async {
            final bytes = await plaintext.fold<List<int>>(
              <int>[],
              (collected, chunk) => collected..addAll(chunk),
            );
            uploads.add((folder: folder, name: fileName, bytes: bytes));
          },
    );
    await sender.open();
    final plain = Uint8List.fromList(const [1, 2, 3, 4]);
    await sender.sendAttachment(
      name: 'cabin.png',
      mime: 'image/png',
      bytes: plain,
    );
    final id = [
      for (final entry in sender.entries)
        if (entry is ChatTimelineMessage) ...entry.attachments,
    ].single.id;

    await sender.saveAttachmentToFolder(id, folder: '/Photos');

    expect(uploads, hasLength(1));
    expect(uploads.single.folder, '/Photos');
    expect(uploads.single.name, 'cabin.png');
    expect(uploads.single.bytes, plain);
    sender.dispose();
  });

  test('an image over 20 MiB is refused before it is downloaded', () async {
    final key = crypto.newChannelKey();
    final id = 'ab' * 32;
    final plain = utf8.encode(
      jsonEncode({
        'v': 1,
        'attachments': [
          {
            'id': id,
            'key': base64Encode(Uint8List(32)),
            'nonce': base64Encode(Uint8List(16)),
            'name': 'big.png',
            'mime': 'image/png',
            'size': ChatMessagesController.maxInlineImageBytes + 1,
          },
        ],
      }),
    );
    quark.messages.add(
      ChatMessage(
        id: 1,
        channelId: _channel,
        authorId: 2,
        keyVersion: 1,
        ciphertext: crypto.encrypt(
          Uint8List.fromList(plain),
          key,
          additionalData: crypto.messageAad(channelId: _channel, keyVersion: 1),
        ),
        createdAt: _epoch,
      ),
    );
    final reader = quark.client(_FakeKeys()..grant(1, key), crypto);
    await reader.open();
    final entry = reader.entries.single as ChatTimelineMessage;
    expect(entry.attachments.single.name, 'big.png');
    await expectLater(
      reader.readImageAttachment(id),
      throwsA(isA<StateError>()),
    );
    expect(quark.attachmentDownloads, 0);
    reader.dispose();
  });

  test('a message under a key not yet granted waits, then opens', () async {
    final key = crypto.newChannelKey();
    final sender = quark.client(_FakeKeys()..grant(1, key), crypto);
    await sender.open();
    await sender.send('secret');

    final waiting = _FakeKeys();
    final reader = quark.client(waiting, crypto);
    await reader.open();
    final entry = reader.entries.single as ChatTimelineMessage;
    expect(entry.state, ChatMessageState.waiting);
    expect(entry.text, isNull);
    await expectLater(
      reader.send('too soon'),
      throwsA(
        isA<MessageException>().having(
          (e) => e.message,
          'message',
          Errors.chatWaitingForKey,
        ),
      ),
    );

    waiting.grant(1, crypto.channelKeyFromBytes(key.extractBytes()));
    expect(texts(reader), ['secret']);

    // Locking forgets the keys, and the text goes with them.
    waiting.forgetAll();
    expect(texts(reader), [null]);
    expect(
      (reader.entries.single as ChatTimelineMessage).state,
      ChatMessageState.waiting,
    );
  });

  test(
    'live events apply, and a reconnect catches up on dropped ones',
    () async {
      final key = crypto.newChannelKey();
      final sender = quark.client(_FakeKeys()..grant(1, key), crypto);
      final reader = quark.client(
        _FakeKeys()..grant(1, crypto.channelKeyFromBytes(key.extractBytes())),
        crypto,
      );
      await reader.open();

      await sender.send('one');
      await pumpEventQueue();
      expect(texts(reader), ['one']);

      quark.drop = true;
      for (final text in ['two', 'three', 'four']) {
        await sender.send(text);
      }
      await pumpEventQueue();
      expect(texts(reader), ['one']);

      quark.reconnects.add(null);
      await pumpEventQueue();
      expect(texts(reader), ['one', 'two', 'three', 'four']);

      await sender.delete(quark.messages.first.id);
      quark.live.add(
        FileEvent(
          kind: 'chat_message_deleted',
          path: '',
          data: {'channelId': _channel, 'messageId': quark.messages.first.id},
        ),
      );
      await pumpEventQueue();
      final first = reader.entries.first as ChatTimelineMessage;
      expect(first.state, ChatMessageState.deleted);
      expect(first.text, isNull);
    },
  );

  test('a ciphertext moved from another channel does not open', () async {
    final key = crypto.newChannelKey();
    final elsewhere = crypto.encrypt(
      Uint8List.fromList(utf8.encode('from channel 8')),
      key,
      additionalData: crypto.messageAad(channelId: 8, keyVersion: 1),
    );
    quark.post(_channel, 1, elsewhere);

    final reader = quark.client(_FakeKeys()..grant(1, key), crypto);
    await reader.open();

    final entry = reader.entries.single as ChatTimelineMessage;
    expect(entry.state, ChatMessageState.unreadable);
    expect(entry.text, isNull);
  });

  test('events merge into the timeline as verified or unverified', () async {
    final key = crypto.newChannelKey();
    final sender = quark.client(_FakeKeys()..grant(1, key), crypto);
    await sender.open();
    ChatChannelEvent event(int id, int minutes, {bool signed = true}) =>
        ChatChannelEvent(
          id: id,
          channelId: _channel,
          kind: ChatChannelEvent.memberSet,
          actorId: 2,
          payload:
              '{"userId":3,"name":"carol","permissions":["read_messages"]}',
          createdAt: _epoch.add(Duration(minutes: minutes)),
          signature: signed ? Uint8List(64) : null,
          signerSignKey: signed ? Uint8List(32) : null,
        );
    quark.events.add(event(1, 1));
    await sender.send('first'); // minute 2
    quark.events.add(event(2, 3, signed: false));
    await sender.send('second'); // minute 4

    final reader = quark.client(
      _FakeKeys()..grant(1, crypto.channelKeyFromBytes(key.extractBytes())),
      crypto,
    );
    await reader.open();

    final entries = reader.entries;
    expect(entries.map((e) => e.runtimeType).toList(), [
      ChatTimelineSystem,
      ChatTimelineMessage,
      ChatTimelineSystem,
      ChatTimelineMessage,
    ]);
    expect((entries[0] as ChatTimelineSystem).isUnverified, isFalse);
    expect((entries[2] as ChatTimelineSystem).isUnverified, isTrue);

    // The actor signs later; chat_channel_changed brings the signature.
    quark.events[1] = event(2, 3);
    quark.live.add(
      const FileEvent(
        kind: 'chat_channel_changed',
        path: '',
        data: {'channelId': _channel},
      ),
    );
    await pumpEventQueue();
    expect((reader.entries[2] as ChatTimelineSystem).isVerified, isTrue);
  });

  group('edit (#2426)', () {
    test('the author edits, and readers see the new text live, with its '
        'reactions kept', () async {
      final key = crypto.newChannelKey();
      final alice = quark.client(_FakeKeys()..grant(1, key), crypto);
      final bob = quark.client(
        _FakeKeys()..grant(1, crypto.channelKeyFromBytes(key.extractBytes())),
        crypto,
        userId: 3,
      );
      await alice.open();
      await bob.open();
      await alice.send('Dinner at 7');
      await pumpEventQueue();
      final id = quark.messages.single.id;
      final before = quark.messages.single.ciphertext!;
      await bob.toggleReaction(id, '👍');
      await pumpEventQueue();

      await alice.edit(id, 'Dinner at 6, traffic');
      await pumpEventQueue();

      expect(texts(alice), ['Dinner at 6, traffic']);
      expect(texts(bob), ['Dinner at 6, traffic']);
      final stored = quark.messages.single.ciphertext!;
      expect(stored.sublist(0, 24), isNot(before.sublist(0, 24)));
      expect(
        utf8.decode(stored, allowMalformed: true),
        isNot(contains('Dinner')),
      );
      final entry = bob.entries.whereType<ChatTimelineMessage>().single;
      expect(entry.message.editedAt, isNotNull);
      expect(entry.reactions.single.emoji, '👍');
      final item = ChatController.itemFor(entry, (_) => 'Ada', me: 3);
      expect(item.isEdited, isTrue);
      expect(item.reactions.single.count, 1);
      alice.dispose();
      bob.dispose();
    });

    test('editing a caption keeps the file', () async {
      final key = crypto.newChannelKey();
      final alice = quark.client(_FakeKeys()..grant(1, key), crypto);
      await alice.open();
      await alice.sendAttachment(
        name: 'cabin.png',
        mime: 'image/png',
        bytes: Uint8List.fromList(const [1, 2, 3, 4]),
        caption: 'look',
      );
      final sent = alice.entries.whereType<ChatTimelineMessage>().single;

      await alice.edit(sent.message.id, 'look at this');

      final reader = quark.client(
        _FakeKeys()..grant(1, crypto.channelKeyFromBytes(key.extractBytes())),
        crypto,
        userId: 3,
      );
      await reader.open();
      final got = reader.entries.whereType<ChatTimelineMessage>().single;
      expect(got.text, 'look at this');
      expect(got.attachments.single.id, sent.attachments.single.id);
      expect(got.attachments.single.key, sent.attachments.single.key);
      alice.dispose();
      reader.dispose();
    });
  });

  group('typing (#2426)', () {
    testWidgets('typing reaches the others, is sent at most every interval, '
        'and lapses on its own or when the message arrives', (tester) async {
      final key = crypto.newChannelKey();
      final alice = quark.client(_FakeKeys()..grant(1, key), crypto);
      final bob = quark.client(
        _FakeKeys()..grant(1, crypto.channelKeyFromBytes(key.extractBytes())),
        crypto,
        userId: 3,
      );
      // In the test's fake time, so the lapse timers are too.
      unawaited(alice.open());
      unawaited(bob.open());
      await tester.pump();

      alice.notifyTyping();
      alice.notifyTyping();
      await tester.pump();
      expect(quark.typings, 1);
      expect(bob.typingUserIds, {2});
      expect(alice.typingUserIds, isEmpty);

      // No stop event: it lapses after the timeout without another.
      await tester.pump(ChatConfig.typingTimeout - const Duration(seconds: 1));
      expect(bob.typingUserIds, {2});
      await tester.pump(const Duration(seconds: 1));
      expect(bob.typingUserIds, isEmpty);

      // After the interval it is said again, and the message clears it.
      alice.notifyTyping();
      await tester.pump();
      expect(quark.typings, 2);
      expect(bob.typingUserIds, {2});
      unawaited(alice.send('on my way'));
      await tester.pump();
      expect(bob.typingUserIds, isEmpty);

      alice.notifyTyping();
      bob.dispose();
      alice.dispose();
      await tester.pump(ChatConfig.typingTimeout);
    });
  });

  group('quote-reply (#2426)', () {
    test('a reply carries its quote inside the ciphertext, quoted from each '
        'reader\'s own copy, and degrades when the original goes', () async {
      final key = crypto.newChannelKey();
      final alice = quark.client(_FakeKeys()..grant(1, key), crypto);
      final bob = quark.client(
        _FakeKeys()..grant(1, crypto.channelKeyFromBytes(key.extractBytes())),
        crypto,
        userId: 3,
      );
      await alice.open();
      await bob.open();
      await alice.send('dentist at 10?');
      await pumpEventQueue();
      final original = quark.messages.single.id;

      await bob.send('yes, 10am', replyTo: original);
      await pumpEventQueue();
      final reply = quark.messages.last;

      // An older client reads it as a message with no files: its text.
      final plain = crypto.decrypt(
        reply.ciphertext!,
        key,
        additionalData: crypto.messageAad(channelId: _channel, keyVersion: 1),
      );
      final decoded = decodeAttachmentMessage(plain)!;
      expect(decoded.text, 'yes, 10am');
      expect(decoded.attachments, isEmpty);
      expect(decoded.replyTo, original);

      ChatQuoteItem? quoteIn(ChatMessagesController c) {
        final byId = {
          for (final e in c.entries.whereType<ChatTimelineMessage>())
            e.message.id: e,
        };
        return ChatController.itemFor(
          byId[reply.id]!,
          (id) => id == 2 ? 'alice' : 'bob',
          quoted: (id) => byId[id],
        ).quote;
      }

      expect(
        quoteIn(alice),
        ChatQuoteItem(
          messageId: '$original',
          authorName: 'alice',
          text: 'dentist at 10?',
        ),
      );

      // Editing the reply keeps what it quotes.
      await bob.edit(reply.id, 'yes, 10:30');
      await pumpEventQueue();
      expect(quoteIn(alice)?.messageId, '$original');
      expect(texts(alice).last, 'yes, 10:30');

      // A deleted original reads as unavailable, never as an error.
      await alice.delete(original);
      await pumpEventQueue();
      expect(
        quoteIn(alice),
        ChatQuoteItem(messageId: '$original', authorName: 'alice'),
      );
      alice.dispose();
      bob.dispose();
    });

    test('a quote the reader has not loaded names no one', () {
      expect(
        ChatController.quoteFor(5, null, (_) => 'x'),
        const ChatQuoteItem(messageId: '5'),
      );
    });
  });

  group('reactions (#2426)', () {
    List<ChatReactionItem> reactionsOf(ChatMessagesController c, int me) =>
        ChatController.reactionItems(
          (c.entries.whereType<ChatTimelineMessage>().first).reactions,
          me,
        );

    test(
      'toggle adds and takes back, and live events keep others current',
      () async {
        final key = crypto.newChannelKey();
        final alice = quark.client(_FakeKeys()..grant(1, key), crypto);
        final bob = quark.client(
          _FakeKeys()..grant(1, crypto.channelKeyFromBytes(key.extractBytes())),
          crypto,
          userId: 3,
        );
        await alice.open();
        await bob.open();
        await alice.send('lunch?');
        await pumpEventQueue();
        final messageId = quark.messages.single.id;

        await bob.toggleReaction(messageId, '👍');
        await alice.toggleReaction(messageId, '👍');
        await alice.toggleReaction(messageId, '🎉');
        await pumpEventQueue();

        // Ciphertext is padded to one length and never holds the emoji.
        final stored = quark.reactions[messageId]!;
        expect(stored.map((r) => r.ciphertext.length).toSet(), {24 + 64 + 16});
        expect(
          utf8.decode(stored.first.ciphertext, allowMalformed: true),
          isNot(contains('👍')),
        );
        expect(reactionsOf(bob, 3), const [
          ChatReactionItem(emoji: '👍', count: 2, reactedByMe: true),
          ChatReactionItem(emoji: '🎉', count: 1),
        ]);

        await bob.toggleReaction(messageId, '👍');
        await pumpEventQueue();
        expect(reactionsOf(alice, 2), const [
          ChatReactionItem(emoji: '👍', count: 1, reactedByMe: true),
          ChatReactionItem(emoji: '🎉', count: 1, reactedByMe: true),
        ]);
        expect(quark.reactions[messageId]!.map((r) => r.userId), [2, 2]);
      },
    );

    // #2949: in an anonymous channel the Quark names reactors by pseudonym,
    // so the reaction's additional data binds the channel's selfId, which
    // the keys controller holds, not the account id.
    test('an anonymous channel binds reactions to the pseudonym', () async {
      _FakeKeys keysAs(int selfId, SecureKey key) => _FakeKeys()
        ..rememberChannels([
          ChatChannel(id: _channel, name: 'c', anonymous: true, selfId: selfId),
        ])
        ..grant(1, key);
      final key = crypto.newChannelKey();
      final alice = quark.client(
        keysAs(-2, key),
        crypto,
        userId: -2,
        selfFromKeys: true,
      );
      final bob = quark.client(
        keysAs(-3, crypto.channelKeyFromBytes(key.extractBytes())),
        crypto,
        userId: -3,
        selfFromKeys: true,
      );
      await alice.open();
      await bob.open();
      await alice.send('lunch?');
      await pumpEventQueue();
      final messageId = quark.messages.single.id;

      await alice.toggleReaction(messageId, '👍');
      await bob.toggleReaction(messageId, '👍');
      await pumpEventQueue();

      expect(quark.reactions[messageId]!.map((r) => r.userId), [-2, -3]);
      expect(reactionsOf(bob, -3), const [
        ChatReactionItem(emoji: '👍', count: 2, reactedByMe: true),
      ]);

      await alice.toggleReaction(messageId, '👍');
      await pumpEventQueue();
      expect(quark.reactions[messageId]!.map((r) => r.userId), [
        -3,
      ], reason: 'alice finds her own reaction by her pseudonym');
    });

    test('a reconnect catches up on dropped reactions and deletions', () async {
      final key = crypto.newChannelKey();
      final alice = quark.client(_FakeKeys()..grant(1, key), crypto);
      final bob = quark.client(
        _FakeKeys()..grant(1, crypto.channelKeyFromBytes(key.extractBytes())),
        crypto,
        userId: 3,
      );
      await alice.open();
      await alice.send('one');
      await alice.send('two');
      await bob.open();
      final [first, second] = [for (final m in quark.messages) m.id];

      quark.drop = true;
      await alice.toggleReaction(first, '❤️');
      await alice.toggleReaction(second, '😂');
      await alice.delete(second);
      await pumpEventQueue();
      expect(reactionsOf(bob, 3), isEmpty);

      quark.reconnects.add(null);
      await pumpEventQueue();
      expect(reactionsOf(bob, 3), const [
        ChatReactionItem(emoji: '❤️', count: 1),
      ]);
      final tombstone = bob.entries.whereType<ChatTimelineMessage>().last;
      expect(tombstone.state, ChatMessageState.deleted);
      expect(tombstone.reactions, isEmpty);
    });

    test('a reaction moved to another message does not open', () async {
      final key = crypto.newChannelKey();
      final alice = quark.client(_FakeKeys()..grant(1, key), crypto);
      await alice.open();
      await alice.send('one');
      await alice.send('two');
      final [first, second] = [for (final m in quark.messages) m.id];
      await alice.toggleReaction(first, '👍');
      final moved = quark.reactions.remove(first)!.single;
      quark.reactions[second] = [
        ChatReaction(
          id: moved.id,
          messageId: second,
          userId: moved.userId,
          keyVersion: moved.keyVersion,
          ciphertext: moved.ciphertext,
          createdAt: moved.createdAt,
        ),
      ];

      final reader = quark.client(
        _FakeKeys()..grant(1, crypto.channelKeyFromBytes(key.extractBytes())),
        crypto,
      );
      await reader.open();
      final last = reader.entries.whereType<ChatTimelineMessage>().last;
      expect(last.reactions.single.emoji, isNull);
      expect(ChatController.reactionItems(last.reactions, 2), isEmpty);
    });
  });

  group('polls (#3894)', () {
    late SecureKey key;
    _FakeKeys keys() =>
        _FakeKeys()..grant(1, crypto.channelKeyFromBytes(key.extractBytes()));

    setUp(() => key = crypto.newChannelKey());

    ChatTimelineMessage only(ChatMessagesController c) =>
        c.entries.whereType<ChatTimelineMessage>().single;
    ChatPollItem pollOf(ChatMessagesController c, int me) =>
        ChatMessagesController.pollItemFor(only(c), me: me);

    const lunch = ChatPollDraft(
      prompt: ' Where for lunch? ',
      options: ['Tacos', '', 'Pho', 'Pizza'],
    );

    /// The author, alice (2), posts [draft]; bob (3) and carol (4) open it.
    Future<List<ChatMessagesController>> postAndOpen(
      ChatPollDraft draft,
    ) async {
      final alice = quark.client(keys(), crypto);
      await alice.open();
      await alice.sendPoll(draft);
      final bob = quark.client(keys(), crypto, userId: 3);
      final carol = quark.client(keys(), crypto, userId: 4);
      await bob.open();
      await carol.open();
      return [alice, bob, carol];
    }

    test('a poll is tallied on every device from the answers', () async {
      final [alice, bob, carol] = await postAndOpen(lunch);
      final id = only(alice).message.id;
      expect(quark.polls[id]!.allowChange, isTrue);

      await bob.answerPoll(id, const ChatPollAnswer(choices: [1]));
      await carol.answerPoll(id, const ChatPollAnswer(choices: [1]));
      await pumpEventQueue();

      final item = ChatController.itemFor(only(alice), (_) => '', me: 2);
      expect(item.kind, ChatMessageKind.poll);
      expect(item.body, 'Where for lunch?');
      expect(item.poll!.options, ['Tacos', 'Pho', 'Pizza']);
      expect(item.poll!.counts, [0, 2, 0]);
      expect(item.poll!.responseCount, 2);
      expect(item.poll!.myAnswer, isNull);
      expect(pollOf(bob, 3).myAnswer, const ChatPollAnswer(choices: [1]));
      expect(pollOf(carol, 4).counts, [0, 2, 0]);
    });

    test('changing an answer replaces it; a poll without that refuses '
        'it', () async {
      final [alice, bob, _] = await postAndOpen(lunch);
      final id = only(alice).message.id;

      await bob.answerPoll(id, const ChatPollAnswer(choices: [0]));
      await bob.answerPoll(id, const ChatPollAnswer(choices: [2]));
      await pumpEventQueue();
      expect(pollOf(alice, 2).counts, [0, 0, 1]);
      expect(pollOf(bob, 3).myAnswer, const ChatPollAnswer(choices: [2]));
      expect(pollOf(bob, 3).responseCount, 1);

      await alice.sendPoll(
        const ChatPollDraft(
          prompt: 'Once only',
          type: ChatPollType.multiple,
          options: ['a', 'b'],
          allowChange: false,
        ),
      );
      final fixed = alice.entries.whereType<ChatTimelineMessage>().last;
      await pumpEventQueue();
      await bob.answerPoll(
        fixed.message.id,
        const ChatPollAnswer(choices: [0, 1]),
      );
      await expectLater(
        bob.answerPoll(fixed.message.id, const ChatPollAnswer(choices: [0])),
        throwsA(isA<ApiException>()),
      );
    });

    test('an anonymous poll names nobody, and still knows your own', () async {
      final [alice, bob, _] = await postAndOpen(
        lunch.copyWith(anonymous: true),
      );
      final id = only(alice).message.id;
      await bob.answerPoll(id, const ChatPollAnswer(choices: [2]));
      await pumpEventQueue();

      final seen = only(alice).pollAnswers.single;
      expect(seen.response.userId, isNull);
      expect(seen.answer, const ChatPollAnswer(choices: [2]));
      expect(pollOf(alice, 2).anonymous, isTrue);
      expect(pollOf(bob, 3).myAnswer, const ChatPollAnswer(choices: [2]));

      // A fresh page marks bob's own the same way.
      final again = quark.client(keys(), crypto, userId: 3);
      await again.open();
      expect(pollOf(again, 3).myAnswer, const ChatPollAnswer(choices: [2]));
    });

    test('results after close stay hidden from readers until it '
        'closes', () async {
      final [alice, bob, carol] = await postAndOpen(
        lunch.copyWith(resultsAfterClose: true),
      );
      final id = only(alice).message.id;
      await bob.answerPoll(id, const ChatPollAnswer(choices: [0]));
      await carol.answerPoll(id, const ChatPollAnswer(choices: [1]));
      await pumpEventQueue();

      expect(pollOf(alice, 2).resultsVisible, isTrue);
      expect(pollOf(alice, 2).responseCount, 2);
      expect(pollOf(carol, 4).resultsVisible, isFalse);
      expect(pollOf(carol, 4).responseCount, 1);
      expect(pollOf(carol, 4).myAnswer, const ChatPollAnswer(choices: [1]));

      await alice.closePoll(id);
      await pumpEventQueue();
      expect(pollOf(carol, 4).isClosed, isTrue);
      expect(pollOf(carol, 4).resultsVisible, isTrue);
      expect(pollOf(carol, 4).counts, [1, 1, 0]);
    });

    test('a closed poll says so and takes no answer', () async {
      final [alice, bob, _] = await postAndOpen(
        lunch.copyWith(closesAt: DateTime.utc(2030)),
      );
      final id = only(alice).message.id;
      expect(pollOf(bob, 3).isClosed, isFalse);
      expect(
        ChatMessagesController.pollItemFor(
          only(bob),
          me: 3,
          now: DateTime.utc(2031),
        ).isClosed,
        isTrue,
      );

      await alice.closePoll(id);
      await pumpEventQueue();
      expect(pollOf(alice, 2).isClosed, isTrue);
      expect(pollOf(bob, 3).isClosed, isTrue);
      await expectLater(
        bob.answerPoll(id, const ChatPollAnswer(choices: [0])),
        throwsA(isA<ApiException>()),
      );
    });

    test('a written answer is tallied as text', () async {
      final [alice, bob, _] = await postAndOpen(
        const ChatPollDraft(prompt: 'Ideas?', type: ChatPollType.text),
      );
      final id = only(alice).message.id;
      await bob.answerPoll(id, const ChatPollAnswer(text: ' a picnic '));
      await pumpEventQueue();
      expect(pollOf(alice, 2).textAnswers, ['a picnic']);
      expect(pollOf(alice, 2).options, isEmpty);
    });

    test('number, date, rating and a second question tally', () async {
      final [alice, bob, _] = await postAndOpen(
        const ChatPollDraft(
          prompt: 'How many?',
          type: ChatPollType.number,
          more: [
            ChatPollQuestionDraft(prompt: 'When?', type: ChatPollType.date),
            ChatPollQuestionDraft(
              prompt: 'How was it?',
              type: ChatPollType.rating,
              scale: 5,
            ),
          ],
        ),
      );
      final id = only(alice).message.id;
      await bob.answerPoll(
        id,
        const ChatPollAnswer(
          parts: [
            ChatPollAnswer(number: '4'),
            ChatPollAnswer(date: '2026-11-08'),
            ChatPollAnswer(rating: 4),
          ],
        ),
      );
      await pumpEventQueue();

      final item = pollOf(alice, 2);
      expect(item.questions, hasLength(3));
      expect(item.type, ChatPollType.number);
      expect(item.textAnswers, ['4']);
      expect(item.questions[1].textAnswers, ['2026-11-08']);
      expect(item.questions[2].ratingCounts, [0, 0, 0, 1, 0]);
      expect(item.responseCount, 1);
      expect(
        pollOf(bob, 3).myAnswer,
        const ChatPollAnswer(
          parts: [
            ChatPollAnswer(number: '4'),
            ChatPollAnswer(date: '2026-11-08'),
            ChatPollAnswer(rating: 4),
          ],
        ),
      );
    });

    test('poll-shaped text without settings, and other JSON, stay '
        'text', () async {
      final alice = quark.client(keys(), crypto);
      await alice.open();
      await alice.send(ChatPollQuestion.fromDraft(lunch).toPayload());
      await alice.send('{"quark":"poll/9","questions":[]}');
      await alice.send('{"a":1}');
      expect([
        for (final e in alice.entries)
          ChatController.itemFor(e, (_) => '', me: 2).kind,
      ], everyElement(ChatMessageKind.text));
    });
  });

  group('side conversations (#4345)', () {
    test('a live reply with a rootId stays out of the timeline', () async {
      final key = crypto.newChannelKey();
      final reader = quark.client(_FakeKeys()..grant(1, key), crypto);
      await reader.open();
      final root = quark.post(
        _channel,
        1,
        crypto.encrypt(
          Uint8List.fromList(utf8.encode('root')),
          key,
          additionalData: crypto.messageAad(channelId: _channel, keyVersion: 1),
        ),
      );
      await pumpEventQueue();

      final reply = crypto.encrypt(
        Uint8List.fromList(utf8.encode('in the branch')),
        key,
        additionalData: crypto.messageAad(
          channelId: _channel,
          keyVersion: 1,
          rootId: root.id,
        ),
      );
      quark.live.add(
        FileEvent(
          kind: 'chat_message_created',
          path: '',
          data: jsonDecode(
            jsonEncode({
              'channelId': _channel,
              'messageId': 99,
              'rootId': root.id,
              'message': {
                'id': 99,
                'channelId': _channel,
                'authorId': 3,
                'keyVersion': 1,
                'ciphertext': base64Encode(reply),
                'createdAt': _epoch.toIso8601String(),
                'rootId': root.id,
              },
            }),
          ),
        ),
      );
      await pumpEventQueue();

      expect(texts(reader), ['root']);
      reader.dispose();
    });

    test('a reply opens under its root, and an edit seals it under the same '
        'root again', () async {
      final key = crypto.newChannelKey();
      Uint8List aad({int? rootId}) =>
          crypto.messageAad(channelId: _channel, keyVersion: 1, rootId: rootId);
      quark.messages.add(
        ChatMessage(
          id: 4,
          channelId: _channel,
          authorId: 2,
          keyVersion: 1,
          ciphertext: crypto.encrypt(
            Uint8List.fromList(utf8.encode('root')),
            key,
            additionalData: aad(),
          ),
          createdAt: _epoch,
        ),
      );
      quark.messages.add(
        ChatMessage(
          id: 5,
          channelId: _channel,
          authorId: 2,
          keyVersion: 1,
          ciphertext: crypto.encrypt(
            Uint8List.fromList(utf8.encode('first')),
            key,
            additionalData: aad(rootId: 4),
          ),
          createdAt: _epoch,
          rootId: 4,
        ),
      );
      // The channel's list leaves replies out: they open in their root's
      // side conversation.
      final author = quark.client(
        _FakeKeys()..grant(1, key),
        crypto,
        rootId: 4,
      );
      await author.open();
      expect(texts(author), ['first']);

      await author.edit(5, 'second');
      await pumpEventQueue();
      expect(texts(author), ['second']);

      final stored = quark.messages.last;
      expect(stored.rootId, 4);
      expect(
        utf8.decode(
          crypto.decrypt(
            stored.ciphertext!,
            key,
            additionalData: aad(rootId: 4),
          ),
        ),
        'second',
      );
      expect(
        () => crypto.decrypt(stored.ciphertext!, key, additionalData: aad()),
        throwsA(anything),
      );
      author.dispose();
    });
  });

  group('side conversation summaries (#4346)', () {
    test('a page carries a root\'s branch, and a live reply raises its chip '
        'with no side conversation open', () async {
      final key = crypto.newChannelKey();
      Uint8List seal(String text, {int? rootId}) => crypto.encrypt(
        Uint8List.fromList(utf8.encode(text)),
        key,
        additionalData: crypto.messageAad(
          channelId: _channel,
          keyVersion: 1,
          rootId: rootId,
        ),
      );
      final lastAt = DateTime.utc(2026, 9, 25, 10, 7);
      quark.messages.add(
        ChatMessage.fromJson({
          'id': 4,
          'channelId': _channel,
          'authorId': 2,
          'keyVersion': 1,
          'ciphertext': base64Encode(seal('the sink is leaking')),
          'createdAt': _epoch.toIso8601String(),
          'branch': {'replyCount': 1, 'lastReplyAt': lastAt.toIso8601String()},
        }),
      );
      final reader = quark.client(_FakeKeys()..grant(1, key), crypto);
      await reader.open();
      ChatBranchItem? chip() => ChatController.itemFor(
        reader.entries.whereType<ChatTimelineMessage>().single,
        (_) => 'Ada',
      ).branch;
      expect(
        chip(),
        ChatBranchItem(replyCount: 1, lastReplyAt: lastAt.toLocal()),
      );

      quark.messages.add(
        ChatMessage(
          id: 5,
          channelId: _channel,
          authorId: 3,
          keyVersion: 1,
          ciphertext: seal('first', rootId: 4),
          createdAt: lastAt,
          rootId: 4,
        ),
      );
      final reply = quark.post(
        _channel,
        1,
        seal('plumber at 3', rootId: 4),
        rootId: 4,
      );
      await pumpEventQueue();
      expect(texts(reader), ['the sink is leaking']);
      expect(
        chip(),
        ChatBranchItem(replyCount: 2, lastReplyAt: reply.createdAt.toLocal()),
      );

      await reader.edit(4, 'the sink is fixed');
      await pumpEventQueue();
      expect(chip()?.replyCount, 2, reason: 'an edit carries no branch');

      quark.live.add(
        FileEvent(
          kind: 'chat_branch_changed',
          path: '',
          data: {'channelId': _channel, 'messageId': 4, 'replyCount': 0},
        ),
      );
      await pumpEventQueue();
      expect(chip(), isNull, reason: 'its last reply was deleted');

      quark.live.add(
        FileEvent(
          kind: 'chat_branch_changed',
          path: '',
          data: {'channelId': _channel, 'messageId': 77, 'replyCount': 3},
        ),
      );
      await pumpEventQueue();
      expect(reader.entries, hasLength(1), reason: 'a root not loaded');
      reader.dispose();
    });
  });

  group('side conversation unread replies (#4349)', () {
    test('a reply from someone else raises a root\'s unread count, one of '
        'this account\'s involves it, and a branch marker sets it', () async {
      final key = crypto.newChannelKey();
      final lastAt = DateTime.utc(2026, 9, 25, 10, 7);
      quark.messages.add(
        ChatMessage.fromJson({
          'id': 4,
          'channelId': _channel,
          'authorId': 4,
          'keyVersion': 1,
          'ciphertext': base64Encode(
            crypto.encrypt(
              Uint8List.fromList(utf8.encode('the sink is leaking')),
              key,
              additionalData: crypto.messageAad(
                channelId: _channel,
                keyVersion: 1,
              ),
            ),
          ),
          'createdAt': _epoch.toIso8601String(),
          'branch': {
            'replyCount': 1,
            'lastReplyAt': lastAt.toIso8601String(),
            'unreadCount': 1,
          },
        }),
      );
      final reader = quark.client(_FakeKeys()..grant(1, key), crypto);
      await reader.open();
      ChatBranch? branch() =>
          reader.entries.whereType<ChatTimelineMessage>().single.message.branch;
      expect(branch()?.unreadCount, 1);
      expect(branch()?.involved, isFalse);

      void emit(String kind, Map<String, Object?> data) => quark.live.add(
        FileEvent(kind: kind, path: '', data: {'channelId': _channel, ...data}),
      );
      Map<String, Object?> reply(int id, int author) => {
        'rootId': 4,
        'message': {
          'id': id,
          'channelId': _channel,
          'authorId': author,
          'keyVersion': 1,
          'rootId': 4,
          'createdAt': lastAt.toIso8601String(),
        },
      };
      emit('chat_message_created', reply(5, 3));
      emit('chat_branch_changed', {
        'messageId': 4,
        'replyCount': 2,
        'lastReplyAt': lastAt.toIso8601String(),
      });
      await pumpEventQueue();
      expect(branch()?.replyCount, 2);
      expect(branch()?.unreadCount, 2, reason: 'the event is everyone\'s');
      expect(texts(reader), ['the sink is leaking'], reason: 'no reply shown');

      emit('chat_message_created', reply(6, 2));
      await pumpEventQueue();
      expect(branch()?.unreadCount, 2);
      expect(branch()?.involved, isTrue);

      emit('chat_read_marker_changed', {
        'rootId': 4,
        'lastReadMessageId': 6,
        'unreadCount': 0,
      });
      emit('chat_read_marker_changed', {
        'lastReadMessageId': 6,
        'unreadCount': 0,
      });
      await pumpEventQueue();
      expect(branch()?.unreadCount, 0);
      reader.dispose();
    });
  });

  group('a side conversation (#4348)', () {
    Uint8List seal(SecureKey key, String text, {int? rootId}) => crypto.encrypt(
      Uint8List.fromList(utf8.encode(text)),
      key,
      additionalData: crypto.messageAad(
        channelId: _channel,
        keyVersion: 1,
        rootId: rootId,
      ),
    );

    test('a reply posts with its root and lands in the side conversation, '
        'not the channel', () async {
      final key = crypto.newChannelKey();
      final channel = quark.client(_FakeKeys()..grant(1, key), crypto);
      await channel.open();
      final root = quark.post(_channel, 1, seal(key, 'the sink'));
      await pumpEventQueue();
      final branch = quark.client(
        _FakeKeys()..grant(1, key),
        crypto,
        rootId: root.id,
      );
      await branch.open();
      expect(branch.root?.text, 'the sink');
      expect(branch.isRootMissing, isFalse);

      await branch.send('on it', clientMessageId: 'c1');
      await pumpEventQueue();

      final stored = quark.messages.last;
      expect(stored.rootId, root.id);
      expect(
        utf8.decode(
          crypto.decrypt(
            stored.ciphertext!,
            key,
            additionalData: crypto.messageAad(
              channelId: _channel,
              keyVersion: 1,
              rootId: root.id,
            ),
          ),
        ),
        'on it',
      );
      expect(texts(branch), ['on it']);
      expect(texts(channel), ['the sink']);
      channel.dispose();
      branch.dispose();
    });

    test('a live reply from someone else lands only in its own side '
        'conversation', () async {
      final key = crypto.newChannelKey();
      final root = quark.post(_channel, 1, seal(key, 'the sink'));
      final other = quark.post(_channel, 1, seal(key, 'dinner'));
      final channel = quark.client(_FakeKeys()..grant(1, key), crypto);
      final branch = quark.client(
        _FakeKeys()..grant(1, key),
        crypto,
        rootId: root.id,
      );
      await channel.open();
      await branch.open();

      quark.post(
        _channel,
        1,
        seal(key, 'plumber at 3', rootId: root.id),
        rootId: root.id,
        authorId: 3,
      );
      quark.post(
        _channel,
        1,
        seal(key, 'pasta', rootId: other.id),
        rootId: other.id,
        authorId: 3,
      );
      await pumpEventQueue();

      expect(texts(branch), ['plumber at 3']);
      expect(texts(channel), ['the sink', 'dinner']);
      channel.dispose();
      branch.dispose();
    });

    test('reconnecting reads the replies again', () async {
      final key = crypto.newChannelKey();
      final root = quark.post(_channel, 1, seal(key, 'the sink'));
      final branch = quark.client(
        _FakeKeys()..grant(1, key),
        crypto,
        rootId: root.id,
      );
      await branch.open();
      final before = quark.replyFetches;

      quark.drop = true;
      quark.post(
        _channel,
        1,
        seal(key, 'missed', rootId: root.id),
        rootId: root.id,
        authorId: 3,
      );
      await pumpEventQueue();
      expect(texts(branch), isEmpty);

      quark.reconnects.add(null);
      await pumpEventQueue();
      expect(quark.replyFetches, greaterThan(before));
      expect(texts(branch), ['missed']);
      branch.dispose();
    });

    test('a root that is no channel message here is missing', () async {
      final key = crypto.newChannelKey();
      final root = quark.post(_channel, 1, seal(key, 'the sink'));
      final reply = quark.post(
        _channel,
        1,
        seal(key, 'a reply', rootId: root.id),
        rootId: root.id,
      );
      for (final id in [reply.id, 999]) {
        final branch = quark.client(
          _FakeKeys()..grant(1, key),
          crypto,
          rootId: id,
        );
        await branch.open();
        expect(branch.isRootMissing, isTrue, reason: '$id');
        expect(branch.entries, isEmpty);
        branch.dispose();
      }
    });
  });
}
