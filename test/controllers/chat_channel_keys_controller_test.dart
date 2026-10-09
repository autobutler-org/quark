import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/chat_channel_keys_controller.dart';
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

const _channel = 7;

/// One channel on a Quark that stores what clients send, the way the real
/// one does: the first grant per member and version wins, and it can't sign.
class _FakeQuark {
  _FakeQuark(this.crypto);

  final ChatCrypto crypto;

  /// Members with published keys, by account.
  final Map<int, ChatIdentity> members = {};
  int current = 0;
  bool rotationNeeded = false;
  final Map<(int, int), ChatKeyGrant> grants = {};
  final List<ChatChannelEvent> events = [];

  /// Grants handed back, as (version, account).
  final List<(int, int)> rejected = [];

  Uint8List signKeyOf(int user) => members[user]!.sign.publicKey;

  ChatChannelKeysController client(int me) => ChatChannelKeysController(
    identity: () => members[me],
    crypto: () => crypto,
    userId: () => me,
    fetchKeys: (channelId) async => ChatChannelKeys(
      currentVersion: current,
      versions: [for (var v = 1; v <= current; v++) v],
      grants: [
        for (final g in grants.values)
          if (g.userId == me) g,
      ],
      rotationNeeded: rotationNeeded,
    ),
    createVersion: (channelId, version, sealedKey, signature) async {
      if (version != current + 1) return null;
      current = version;
      rotationNeeded = false;
      grants[(version, me)] = ChatKeyGrant(
        version: version,
        userId: me,
        sealedKey: sealedKey,
        grantedBy: me,
        granterSignKey: signKeyOf(me),
        signature: signature,
      );
      final event = ChatChannelEvent(
        id: events.length + 1,
        channelId: channelId,
        kind: ChatChannelEvent.keyCreated,
        actorId: me,
        payload: '{"version":$version}',
        createdAt: DateTime.utc(2026),
      );
      events.add(event);
      return event;
    },
    fetchPending: (channelId) async => ChatPendingGrants(
      pending: [
        for (var v = 1; v <= current; v++)
          if (grants.containsKey((v, me)))
            for (final entry in members.entries)
              if (!grants.containsKey((v, entry.key)))
                ChatPendingGrant(
                  version: v,
                  userId: entry.key,
                  boxPublicKey: entry.value.box.publicKey,
                ),
      ],
      currentVersion: current,
      rotationNeeded: rotationNeeded,
    ),
    uploadGrants: (channelId, uploads) async {
      for (final g in uploads) {
        grants.putIfAbsent(
          (g.version, g.userId),
          () => ChatKeyGrant(
            version: g.version,
            userId: g.userId,
            sealedKey: g.sealedKey,
            grantedBy: me,
            granterSignKey: signKeyOf(me),
            signature: g.signature,
          ),
        );
      }
    },
    signEvent: (channelId, eventId, signature) async {
      final i = events.indexWhere((e) => e.id == eventId);
      final e = events[i];
      events[i] = ChatChannelEvent(
        id: e.id,
        channelId: e.channelId,
        kind: e.kind,
        actorId: e.actorId,
        payload: e.payload,
        createdAt: e.createdAt,
        signature: signature,
        signerSignKey: signKeyOf(me),
      );
    },
    rejectGrant: (channelId, version) async {
      // This fake holds one channel's grants; another channel has none.
      if (channelId != _channel) return;
      rejected.add((version, me));
      grants.remove((version, me));
    },
  );
}

/// Real libsodium against a fake Quark (#2417). Accounts: 1 alice, 2 bob,
/// 3 carol.
void main() {
  late ChatCrypto crypto;
  late _FakeQuark quark;

  setUpAll(() async => crypto = await ChatCrypto.load());
  setUp(() => quark = _FakeQuark(crypto));

  void publish(int user) => quark.members[user] = crypto.generateIdentity();

  /// Whether [a] and [b] opened the same key for [version].
  void sameKey(
    ChatChannelKeysController a,
    ChatChannelKeysController b,
    int v,
  ) {
    final message = Uint8List.fromList(utf8.encode('hi'));
    final sealed = crypto.encrypt(message, a.keyFor(_channel, v)!);
    expect(crypto.decrypt(sealed, b.keyFor(_channel, v)!), message);
  }

  test('the first member to open a channel creates version 1', () async {
    publish(1);
    final alice = quark.client(1);

    expect(await alice.ensureKeys(_channel), isFalse);

    expect(quark.current, 1);
    expect(alice.currentVersion(_channel), 1);
    expect(alice.keyFor(_channel, 1), isNotNull);
    final event = quark.events.single;
    expect(alice.verifyEvent(event), isTrue);
  });

  test('a member waits until someone shares the key, then opens it', () async {
    publish(1);
    final alice = quark.client(1);
    await alice.ensureKeys(_channel);
    publish(2);
    final bob = quark.client(2);

    expect(await bob.ensureKeys(_channel), isTrue);
    expect(bob.isWaiting(_channel), isTrue);
    expect(bob.keyFor(_channel, 1), isNull);
    expect(quark.current, 1, reason: 'a waiting member must not rotate');

    await alice.ensureKeys(_channel);
    expect(await bob.ensureKeys(_channel), isFalse);
    expect(bob.isWaiting(_channel), isFalse);
    sameKey(alice, bob, 1);
  });

  test('a forged or misaddressed grant is rejected', () async {
    publish(1);
    publish(2);
    final alice = quark.client(1);
    await alice.ensureKeys(_channel);
    final real = quark.grants[(1, 2)]!;
    final mallory = crypto.generateIdentity();
    // The Quark swaps in a key of its own, signed by a key that isn't
    // alice's but claiming to be hers.
    final forgedKey = crypto.seal(
      crypto.newChannelKey().extractBytes(),
      quark.members[2]!.box.publicKey,
    );
    quark.grants[(1, 2)] = ChatKeyGrant(
      version: 1,
      userId: 2,
      sealedKey: forgedKey,
      grantedBy: 1,
      granterSignKey: quark.signKeyOf(1),
      signature: crypto.sign(
        crypto.grantMessage(
          channelId: _channel,
          version: 1,
          userId: 2,
          sealedKey: forgedKey,
        ),
        mallory,
      ),
    );
    final bob = quark.client(2);

    expect(await bob.ensureKeys(_channel), isTrue);
    expect(bob.keyFor(_channel, 1), isNull);
    expect(quark.rejected, [(1, 2)], reason: 'bob hands the forgery back');
    expect(quark.grants[(1, 2)], isNull);

    // alice's real grant, replayed as if for another channel, fails too.
    final replayed = quark.client(2);
    quark.grants[(1, 2)] = real;
    expect(await replayed.ensureKeys(_channel + 1), isTrue);

    expect(await replayed.ensureKeys(_channel), isFalse);
    sameKey(alice, replayed, 1);
  });

  test('a signed grant that won\'t open is handed back and refilled', () async {
    publish(1);
    publish(2);
    publish(3);
    final alice = quark.client(1);
    await alice.ensureKeys(_channel);
    // carol, a member, squats bob's grant first: signed by her, but sealed
    // to nobody's key.
    final garbage = crypto.seal(
      crypto.newChannelKey().extractBytes(),
      crypto.generateIdentity().box.publicKey,
    );
    quark.grants[(1, 2)] = ChatKeyGrant(
      version: 1,
      userId: 2,
      sealedKey: garbage,
      grantedBy: 3,
      granterSignKey: quark.signKeyOf(3),
      signature: crypto.sign(
        crypto.grantMessage(
          channelId: _channel,
          version: 1,
          userId: 2,
          sealedKey: garbage,
        ),
        quark.members[3]!,
      ),
    );
    final bob = quark.client(2);

    expect(await bob.ensureKeys(_channel), isTrue);
    expect(quark.rejected, [(1, 2)]);
    // Now pending again, so alice's next pass fills a grant that opens.
    await alice.ensureKeys(_channel);
    expect(await bob.ensureKeys(_channel), isFalse);
    sameKey(alice, bob, 1);
  });

  test('rotation creates the next version for the remaining members', () async {
    publish(1);
    publish(2);
    final alice = quark.client(1);
    await alice.ensureKeys(_channel);
    quark.rotationNeeded = true;

    expect(await alice.ensureKeys(_channel), isFalse);

    expect(quark.current, 2);
    expect(alice.currentVersion(_channel), 2);
    final bob = quark.client(2);
    expect(await bob.ensureKeys(_channel), isFalse);
    sameKey(alice, bob, 1);
    sameKey(alice, bob, 2);
  });

  test('chat_key_needed has a holder share the key unprompted', () async {
    publish(1);
    final alice = quark.client(1);
    await alice.ensureKeys(_channel);
    final events = StreamController<FileEvent>();
    alice.start(events: events.stream, lockSignal: ChangeNotifier());
    publish(3);

    events.add(
      const FileEvent(
        kind: 'chat_key_needed',
        path: '',
        data: {'channelId': _channel},
      ),
    );
    for (var i = 0; i < 100 && !quark.grants.containsKey((1, 3)); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final carol = quark.client(3);
    expect(await carol.ensureKeys(_channel), isFalse);
    sameKey(alice, carol, 1);
    await events.close();
  });

  /// The member_set or member_removed event alice's change of account
  /// [userId] came back with, unsigned.
  ChatChannelEvent memberEvent(
    int userId,
    Set<ChatPermission>? permissions, {
    int actor = 1,
  }) {
    final names = permissions?.map((p) => '"${p.id}"').join(',');
    final event = ChatChannelEvent(
      id: quark.events.length + 1,
      channelId: _channel,
      kind: permissions == null
          ? ChatChannelEvent.memberRemoved
          : ChatChannelEvent.memberSet,
      actorId: actor,
      payload: permissions == null
          ? '{"userId":$userId,"name":"u$userId"}'
          : '{"userId":$userId,"name":"u$userId","permissions":[$names]}',
      createdAt: DateTime.utc(2026),
    );
    quark.events.add(event);
    return event;
  }

  test('adding a member fills their grant without any event', () async {
    // #2624: the account that adds a member shares the key as soon as the
    // Quark accepts the change, not when chat_key_needed reaches it.
    publish(1);
    final alice = quark.client(1);
    await alice.ensureKeys(_channel);
    publish(3);
    final permissions = ChatPermissionPreset.member.permissions;

    await alice.signMemberChange(
      memberEvent(3, permissions),
      userId: 3,
      permissions: permissions,
    );

    expect(quark.grants.containsKey((1, 3)), isTrue);
    expect(alice.verifyEvent(quark.events.last), isTrue);
    final carol = quark.client(3);
    expect(await carol.ensureKeys(_channel), isFalse);
    sameKey(alice, carol, 1);
  });

  test('leaving a channel asks nothing more of its keys', () async {
    publish(1);
    publish(2);
    final alice = quark.client(1);
    await alice.ensureKeys(_channel);
    var fetches = 0;
    final bob = ChatChannelKeysController(
      identity: () => quark.members[2],
      crypto: () => crypto,
      userId: () => 2,
      fetchKeys: (_) async {
        fetches++;
        throw StateError('bob is no longer a member');
      },
      signEvent: (_, _, _) async {},
    );

    await bob.signMemberChange(memberEvent(2, null, actor: 2), userId: 2);

    expect(fetches, 0);
  });

  test('events sign and verify, and a tampered one does not', () async {
    publish(1);
    final alice = quark.client(1);
    await alice.ensureKeys(_channel);
    final signed = quark.events.single;
    final tampered = ChatChannelEvent(
      id: signed.id,
      channelId: signed.channelId,
      kind: signed.kind,
      actorId: signed.actorId,
      payload: '{"version":9}',
      createdAt: signed.createdAt,
      signature: signed.signature,
      signerSignKey: signed.signerSignKey,
    );

    expect(alice.verifyEvent(signed), isTrue);
    expect(alice.verifyEvent(tampered), isFalse);
    await expectLater(
      alice.signEvent(
        ChatChannelEvent(
          id: 99,
          channelId: _channel,
          kind: ChatChannelEvent.memberSet,
          actorId: 2,
          payload: '{}',
          createdAt: DateTime.utc(2026),
        ),
      ),
      throwsArgumentError,
    );
  });

  test('a locked chat refuses to fetch keys', () async {
    final locked = quark.client(1);
    await expectLater(locked.ensureKeys(_channel), throwsStateError);
  });
}
