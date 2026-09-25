import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/chat_keys.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/utils/error_text.dart';

/// Argon2id's floor, so the suite spends its time on logic rather than the
/// KDF. The shipped cost is [KdfParams.standard].
const _cheap = KdfParams(opsLimit: 1, memLimit: 8192);

/// Real libsodium, built for the test host by the `sodium` package's build
/// hook (#2416).
void main() {
  late ChatCrypto crypto;

  setUpAll(() async => crypto = await ChatCrypto.load());

  test('wrap and unwrap round-trip the identity', () {
    final identity = crypto.generateIdentity();
    final wrapped = crypto.wrap(identity, 'hunter22-password', _cheap);

    final opened = crypto.unwrap(wrapped, 'hunter22-password', _cheap);

    expect(opened.box.publicKey, identity.box.publicKey);
    expect(opened.sign.publicKey, identity.sign.publicKey);
    expect(opened.seeds, identity.seeds);
  });

  test('a wrong password fails with text Errors shows as written', () {
    final wrapped = crypto.wrap(crypto.generateIdentity(), 'right-one', _cheap);

    Object? thrown;
    try {
      crypto.unwrap(wrapped, 'wrong-one', _cheap);
    } catch (e) {
      thrown = e;
    }

    expect(thrown, isA<MessageException>());
    expect(
      Errors.message(thrown, 'unlock your messages'),
      Errors.chatKeysWrongPassword,
    );
  });

  test('each wrap draws a fresh salt and nonce', () {
    final identity = crypto.generateIdentity();
    final a = crypto.wrap(identity, 'same', _cheap);
    final b = crypto.wrap(identity, 'same', _cheap);

    expect(a.salt, isNot(b.salt));
    expect(a.wrapped, isNot(b.wrapped));
  });

  test('a sealed box opens only for its recipient', () {
    final alice = crypto.generateIdentity();
    final bob = crypto.generateIdentity();
    final message = Uint8List.fromList(utf8.encode('channel key'));

    final sealed = crypto.seal(message, bob.box.publicKey);

    expect(crypto.openSealed(sealed, bob), message);
    expect(() => crypto.openSealed(sealed, alice), throwsA(anything));
  });

  test('a signature verifies only for its signer and message', () {
    final alice = crypto.generateIdentity();
    final bob = crypto.generateIdentity();
    final message = Uint8List.fromList(utf8.encode('grant v1'));

    final signature = crypto.sign(message, alice);

    expect(crypto.verify(message, signature, alice.sign.publicKey), isTrue);
    expect(crypto.verify(message, signature, bob.sign.publicKey), isFalse);
    expect(
      crypto.verify(
        Uint8List.fromList(utf8.encode('grant v2')),
        signature,
        alice.sign.publicKey,
      ),
      isFalse,
    );
  });

  test('channel encryption round-trips and rejects the wrong key', () {
    final key = crypto.newChannelKey();
    final other = crypto.newChannelKey();
    final message = Uint8List.fromList(utf8.encode('hello'));
    final ad = Uint8List.fromList([1, 2, 3]);

    final sealed = crypto.encrypt(message, key, additionalData: ad);

    expect(crypto.decrypt(sealed, key, additionalData: ad), message);
    expect(
      () => crypto.decrypt(sealed, other, additionalData: ad),
      throwsA(anything),
    );
    expect(() => crypto.decrypt(sealed, key), throwsA(anything));
    final copy = crypto.channelKeyFromBytes(key.extractBytes());
    expect(crypto.decrypt(sealed, copy, additionalData: ad), message);
  });

  test('seeds rebuild the same identity', () {
    final identity = crypto.generateIdentity();

    final rebuilt = crypto.identityFromSeeds(
      Uint8List.fromList(identity.seeds),
    );

    expect(rebuilt.box.publicKey, identity.box.publicKey);
    expect(rebuilt.sign.publicKey, identity.sign.publicKey);
  });

  test('a signed grant verifies only for its channel, version and '
      'recipient', () {
    final granter = crypto.generateIdentity();
    final recipient = crypto.generateIdentity();
    final key = crypto.newChannelKey();
    final sealed = crypto.seal(key.extractBytes(), recipient.box.publicKey);
    Uint8List message({int channel = 7, int version = 1, int user = 3}) =>
        crypto.grantMessage(
          channelId: channel,
          version: version,
          userId: user,
          sealedKey: sealed,
        );
    final signature = crypto.sign(message(), granter);
    final signKey = granter.sign.publicKey;

    expect(crypto.verify(message(), signature, signKey), isTrue);
    expect(crypto.openSealed(sealed, recipient), key.extractBytes());
    expect(crypto.verify(message(channel: 8), signature, signKey), isFalse);
    expect(crypto.verify(message(version: 2), signature, signKey), isFalse);
    expect(crypto.verify(message(user: 4), signature, signKey), isFalse);
    final tampered = Uint8List.fromList(sealed)..[0] ^= 1;
    expect(
      crypto.verify(
        crypto.grantMessage(
          channelId: 7,
          version: 1,
          userId: 3,
          sealedKey: tampered,
        ),
        signature,
        signKey,
      ),
      isFalse,
    );
    // Signed by someone else, claiming to be the granter.
    final forger = crypto.generateIdentity();
    expect(
      crypto.verify(message(), crypto.sign(message(), forger), signKey),
      isFalse,
    );
  });

  test('ids above 32 bits are encoded big-endian in full', () {
    final low = crypto.eventMessage(
      channelId: 1,
      eventId: 1,
      actorId: 1,
      kind: 'k',
      payload: '{}',
    );
    final high = crypto.eventMessage(
      channelId: 1 + (1 << 32),
      eventId: 1,
      actorId: 1,
      kind: 'k',
      payload: '{}',
    );
    const prefix = 'quark-chat-event-v1'.length + 1;
    expect(low.sublist(prefix, prefix + 8), [0, 0, 0, 0, 0, 0, 0, 1]);
    expect(high.sublist(prefix, prefix + 8), [0, 0, 0, 1, 0, 0, 0, 1]);
  });
}
