import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/chat_channel_keys_controller.dart';
import 'package:quark/controllers/chat_controller.dart';
import 'package:quark/controllers/chat_messages_controller.dart';
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/models/chat_message.dart';
import 'package:quark/models/chat_poll.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/events_service.dart';
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
  int _nextId = 1;

  ChatMessagesController client(
    _FakeKeys keys,
    ChatCrypto crypto, {
    int userId = 2,
  }) => ChatMessagesController(
    channelId: _channel,
    keys: keys,
    crypto: () => crypto,
    fetchMessages: (channelId, {before, after, limit}) async {
      final n = limit ?? 50;
      final inChannel = messages.where((m) => m.channelId == channelId);
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
    postMessage:
        (channelId, keyVersion, ciphertext, {clientMessageId, poll}) async {
          final stored = byClientId[clientMessageId];
          if (stored != null) return stored;
          final message = post(channelId, keyVersion, ciphertext, poll: poll);
          if (clientMessageId != null) byClientId[clientMessageId] = message;
          if (loseResponse) {
            loseResponse = false;
            throw Exception('timed out');
          }
          return message;
        },
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
    currentUserId: () => userId,
    fetchEvents: (channelId, {after = 0}) async =>
        events.where((e) => e.id > after).toList(),
    events: live.stream.where((e) => audience[e]?.contains(userId) ?? true),
    reconnects: reconnects.stream,
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

  ChatMessage post(
    int channelId,
    int keyVersion,
    Uint8List ciphertext, {
    ChatPoll? poll,
  }) {
    final id = _nextId++;
    final message = ChatMessage(
      id: id,
      channelId: channelId,
      authorId: 2,
      keyVersion: keyVersion,
      ciphertext: ciphertext,
      createdAt: _epoch.add(Duration(minutes: id * 2)),
      poll: poll,
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
              'message': {
                'id': id,
                'channelId': channelId,
                'authorId': 2,
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
}
