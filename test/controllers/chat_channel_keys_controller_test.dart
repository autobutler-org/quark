import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/chat_channel_keys_controller.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/models/chat_keys.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

const _channel = 7;

/// One channel on a Quark that stores what clients send, the way the real
/// one does: the first grant per member and version wins, and it can't sign.
class _FakeQuark {
  _FakeQuark(this.crypto);

  final ChatCrypto crypto;

  /// The identity each client holds, by the id the channel knows it by.
  final Map<int, ChatIdentity> members = {};

  /// The public keys the Quark serves for each id: account keys, or in an
  /// anonymous channel (#2949) the keys a client published for it.
  final Map<int, ChatPublicKeys> published = {};

  /// Ids the channel list leaves out, as it does an admin not in the channel.
  final Set<int> unlisted = {};

  /// How many times each id published channel keys.
  final Map<int, int> puts = {};
  int current = 0;
  bool rotationNeeded = false;
  final Map<(int, int), ChatKeyGrant> grants = {};
  final List<ChatChannelEvent> events = [];

  /// Grants handed back, as (version, account).
  final List<(int, int)> rejected = [];

  Uint8List signKeyOf(int user) => published[user]!.signPublicKey;

  /// A client for [me], the id the channel knows it by. In an anonymous
  /// channel (#2949) that is a pseudonym, and [account] is the account id
  /// behind it.
  ChatChannelKeysController client(int me, {int? account}) {
    Future<ChatChannelEvent?> store(
      int channelId,
      int version,
      Uint8List sealedKey,
      Uint8List signature,
    ) async {
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
    }

    return ChatChannelKeysController(
      identity: () => members[me],
      crypto: () => crypto,
      userId: () => account ?? me,
      listChannels: () async => [
        if (!unlisted.contains(me))
          ChatChannel(
            id: _channel,
            name: 'c',
            anonymous: account != null,
            selfId: account == null ? null : me,
          ),
      ],
      putChannelKeys: (channelId, keys) async {
        if (account == null) return null;
        puts[me] = (puts[me] ?? 0) + 1;
        published[me] = keys;
        return me;
      },
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
        // The ordinary route refuses a version nobody's departure asked for.
        if (current > 0 && !rotationNeeded) return null;
        return store(channelId, version, sealedKey, signature);
      },
      regenerateVersion: store,
      fetchPending: (channelId) async => ChatPendingGrants(
        pending: [
          for (var v = 1; v <= current; v++)
            if (grants.containsKey((v, me)))
              for (final entry in published.entries)
                if (!grants.containsKey((v, entry.key)))
                  ChatPendingGrant(
                    version: v,
                    userId: entry.key,
                    boxPublicKey: entry.value.boxPublicKey,
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
}

/// Real libsodium against a fake Quark (#2417). Accounts: 1 alice, 2 bob,
/// 3 carol.
void main() {
  late ChatCrypto crypto;
  late _FakeQuark quark;

  setUpAll(() async => crypto = await ChatCrypto.load());
  setUp(() => quark = _FakeQuark(crypto));

  /// Gives [user] an identity and publishes its account keys.
  void publish(int user) {
    final identity = crypto.generateIdentity();
    quark.members[user] = identity;
    quark.published[user] = identity.publicKeys;
  }

  /// Gives [user] an account identity the Quark serves nowhere: in an
  /// anonymous channel only the keys its client publishes count.
  void enroll(int user) => quark.members[user] = crypto.generateIdentity();

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
      listChannels: () async => const [],
      putChannelKeys: (_, _) async => null,
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

  test(
    'an admin regenerates a stuck channel and grants everyone with keys',
    () async {
      publish(1);
      final alice = quark.client(1);
      await alice.ensureKeys(_channel);
      publish(2);
      publish(3);
      final admin = quark.client(3);

      expect(await admin.ensureKeys(_channel), isTrue);
      expect(
        quark.current,
        1,
        reason: 'waiting must not use the ordinary route',
      );

      await admin.regenerate(_channel);

      expect(quark.current, 2);
      expect(admin.isWaiting(_channel), isFalse);
      expect(admin.verifyEvent(quark.events.last), isTrue);
      expect(quark.grants.containsKey((2, 1)), isTrue);
      expect(quark.grants.containsKey((2, 2)), isTrue);
      expect(quark.grants.containsKey((1, 2)), isFalse);
      expect(quark.grants.containsKey((1, 3)), isFalse);

      final bob = quark.client(2);
      expect(await bob.ensureKeys(_channel), isFalse);
      expect(bob.keyFor(_channel, 1), isNull);
      sameKey(admin, bob, 2);
    },
  );

  // #2949: in an anonymous channel the Quark names everyone by pseudonym,
  // so a client binds its selfId where it would bind its account id, and
  // seals and signs with its channel identity, never its account's.
  test('an anonymous channel binds and signs the pseudonym', () async {
    const alicePseudonym = -11, bobPseudonym = -12;
    enroll(alicePseudonym);
    enroll(bobPseudonym);
    final alice = quark.client(alicePseudonym, account: 1);
    final aliceAccount = quark.members[alicePseudonym]!;
    final aliceHere = crypto.channelIdentity(aliceAccount, _channel);

    expect(await alice.ensureKeys(_channel), isFalse);
    expect(alice.selfIdIn(_channel), alicePseudonym);
    expect(
      quark.published[alicePseudonym]!.signPublicKey,
      aliceHere.sign.publicKey,
      reason: 'she published her channel keys, not her account keys',
    );
    final own = quark.grants[(1, alicePseudonym)]!;
    final ownMessage = crypto.grantMessage(
      channelId: _channel,
      version: 1,
      userId: alicePseudonym,
      sealedKey: own.sealedKey,
    );
    expect(
      crypto.verify(ownMessage, own.signature, aliceHere.sign.publicKey),
      isTrue,
      reason: 'her own grant is signed over her pseudonym with her channel key',
    );
    expect(
      crypto.verify(ownMessage, own.signature, aliceAccount.sign.publicKey),
      isFalse,
    );
    expect(crypto.openSealed(own.sealedKey, aliceHere), hasLength(32));
    final created = quark.events.single;
    expect(created.actorId, alicePseudonym);
    expect(created.signerSignKey, aliceHere.sign.publicKey);
    expect(alice.verifyEvent(created), isTrue);
    expect(
      quark.grants.containsKey((1, bobPseudonym)),
      isFalse,
      reason: 'bob is not pending until his app publishes channel keys',
    );

    final bob = quark.client(bobPseudonym, account: 2);
    expect(await bob.ensureKeys(_channel), isTrue);
    await alice.ensureKeys(_channel);
    final bobHere = crypto.channelIdentity(
      quark.members[bobPseudonym]!,
      _channel,
    );
    final toBob = quark.grants[(1, bobPseudonym)]!;
    expect(crypto.openSealed(toBob.sealedKey, bobHere), hasLength(32));
    expect(
      () => crypto.openSealed(toBob.sealedKey, quark.members[bobPseudonym]!),
      throwsA(anything),
      reason: 'the grant is sealed to his channel key',
    );
    expect(await bob.ensureKeys(_channel), isFalse);
    sameKey(alice, bob, 1);

    await alice.signEvent(memberEvent(bobPseudonym, {}, actor: alicePseudonym));
    expect(quark.puts, {alicePseudonym: 1, bobPseudonym: 1});

    await expectLater(
      alice.signEvent(
        ChatChannelEvent(
          id: 99,
          channelId: _channel,
          kind: ChatChannelEvent.memberSet,
          actorId: 1,
          payload: '{}',
          createdAt: DateTime.utc(2026),
        ),
      ),
      throwsArgumentError,
      reason: 'an event naming her account id is not hers here',
    );
  });

  test('a channel list publishes keys for its anonymous channels', () async {
    const alicePseudonym = -11;
    enroll(alicePseudonym);
    final alice = quark.client(alicePseudonym, account: 1);

    alice.rememberChannels([
      const ChatChannel(
        id: _channel,
        name: 'c',
        anonymous: true,
        selfId: alicePseudonym,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(quark.puts, {alicePseudonym: 1});
    await alice.ensureKeys(_channel);
    expect(quark.puts, {alicePseudonym: 1}, reason: 'once per session');
  });

  test('an admin outside an anonymous channel signs its member change, '
      'and regenerates over its pseudonym once in it', () async {
    const alicePseudonym = -11, adminPseudonym = -13;
    enroll(alicePseudonym);
    enroll(adminPseudonym);
    final alice = quark.client(alicePseudonym, account: 1);
    await alice.ensureKeys(_channel);
    quark.unlisted.add(adminPseudonym);
    final admin = quark.client(adminPseudonym, account: 3);
    final adminHere = crypto.channelIdentity(
      quark.members[adminPseudonym]!,
      _channel,
    );
    final permissions = ChatPermissionPreset.member.permissions;

    // The admin adds itself: the Quark's member_set names its pseudonym as
    // actor and target, which only publishing keys tells it.
    await admin.signMemberChange(
      memberEvent(adminPseudonym, permissions, actor: adminPseudonym),
      userId: adminPseudonym,
      permissions: permissions,
    );
    final added = quark.events.last;
    expect(added.signature, isNotNull);
    expect(added.signerSignKey, adminHere.sign.publicKey);
    expect(admin.verifyEvent(added), isTrue);
    expect(admin.selfIdIn(_channel), adminPseudonym);

    quark.unlisted.remove(adminPseudonym);
    await admin.regenerate(_channel);

    final own = quark.grants[(2, adminPseudonym)]!;
    expect(
      crypto.verify(
        crypto.grantMessage(
          channelId: _channel,
          version: 2,
          userId: adminPseudonym,
          sealedKey: own.sealedKey,
        ),
        own.signature,
        adminHere.sign.publicKey,
      ),
      isTrue,
      reason: 'the regenerated grant is signed over the pseudonym',
    );
    expect(quark.events.last.actorId, adminPseudonym);
    expect(admin.verifyEvent(quark.events.last), isTrue);
    expect(quark.puts[adminPseudonym], 1);
  });

  test('a locked chat refuses to fetch keys', () async {
    final locked = quark.client(1);
    await expectLater(locked.ensureKeys(_channel), throwsStateError);
  });
}
