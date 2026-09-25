import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/chat_channel_keys_controller.dart';
import 'package:quark/controllers/chat_messages_controller.dart';
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/models/chat_message.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/error_text.dart';
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
  final live = StreamController<FileEvent>.broadcast();
  final reconnects = StreamController<void>.broadcast();
  bool drop = false;
  int _nextId = 1;

  ChatMessagesController client(_FakeKeys keys, ChatCrypto crypto) =>
      ChatMessagesController(
        channelId: _channel,
        keys: keys,
        crypto: () => crypto,
        fetchMessages: (channelId, {before, after, limit}) async {
          final n = limit ?? 50;
          final inChannel = messages.where((m) => m.channelId == channelId);
          if (after != null) {
            return inChannel.where((m) => m.id > after).take(n).toList();
          }
          final older = inChannel
              .where((m) => before == null || m.id < before)
              .toList();
          return older.sublist(older.length > n ? older.length - n : 0);
        },
        postMessage: (channelId, keyVersion, ciphertext) async =>
            post(channelId, keyVersion, ciphertext),
        deleteMessage: (id) async {
          final i = messages.indexWhere((m) => m.id == id);
          messages[i] = messages[i].tombstone(_epoch);
          return messages[i];
        },
        fetchEvents: (channelId, {after = 0}) async =>
            events.where((e) => e.id > after).toList(),
        events: live.stream,
        reconnects: reconnects.stream,
      );

  ChatMessage post(int channelId, int keyVersion, Uint8List ciphertext) {
    final id = _nextId++;
    final message = ChatMessage(
      id: id,
      channelId: channelId,
      authorId: 2,
      keyVersion: keyVersion,
      ciphertext: ciphertext,
      createdAt: _epoch.add(Duration(minutes: id * 2)),
    );
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
    expect(reader.isWaitingForKey, isTrue);
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
          payload: '{"userId":3,"name":"carol","level":"write"}',
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
}
