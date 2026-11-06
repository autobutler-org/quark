import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:sodium/sodium.dart';

/// Real libsodium, same as [chat_crypto_test.dart].
void main() {
  late ChatCrypto crypto;

  setUpAll(() async => crypto = await ChatCrypto.load());

  Future<Uint8List> roundTrip(Uint8List plain) async {
    final key = crypto.newAttachmentKey();
    final prefix = crypto.newAttachmentNoncePrefix();
    addTearDown(key.dispose);
    final sealed = await crypto
        .sealAttachment(
          key: key,
          noncePrefix: prefix,
          input: _slices(plain),
          totalBytes: plain.length,
        )
        .toList();
    final opened = await crypto
        .openAttachment(
          key: key,
          noncePrefix: prefix,
          input: Stream.fromIterable(sealed),
          totalBytes: plain.length,
        )
        .toList();
    return _concat(opened);
  }

  test('an empty file seals to nothing and opens back', () async {
    expect(await roundTrip(Uint8List(0)), isEmpty);
  });

  test('a short file and a file on a chunk boundary round-trip', () async {
    expect(await roundTrip(Uint8List.fromList([1, 2, 3, 4])), [1, 2, 3, 4]);

    final exact = Uint8List(ChatCrypto.attachmentChunkBytes);
    for (var i = 0; i < exact.length; i += 997) {
      exact[i] = i & 0xff;
    }
    expect(await roundTrip(exact), exact);

    final over = Uint8List(ChatCrypto.attachmentChunkBytes + 1);
    over[0] = 7;
    over[ChatCrypto.attachmentChunkBytes] = 9;
    expect(await roundTrip(over), over);
  });

  test(
    'two chunks plus a tail round-trip, and so does a byte at a time',
    () async {
      final plain = Uint8List(ChatCrypto.attachmentChunkBytes * 2 + 50);
      for (var i = 0; i < plain.length; i += 1000) {
        plain[i] = 0xa5;
      }
      expect(await roundTrip(plain), plain);

      final small = Uint8List.fromList(List.generate(100, (i) => i));
      final key = crypto.newAttachmentKey();
      final prefix = crypto.newAttachmentNoncePrefix();
      addTearDown(key.dispose);
      final sealed = _concat(
        await crypto
            .sealAttachment(
              key: key,
              noncePrefix: prefix,
              input: Stream.fromIterable([
                for (final byte in small) [byte],
              ]),
              totalBytes: small.length,
            )
            .toList(),
      );
      final opened = _concat(
        await crypto
            .openAttachment(
              key: key,
              noncePrefix: prefix,
              input: Stream.fromIterable([
                for (final byte in sealed) [byte],
              ]),
              totalBytes: small.length,
            )
            .toList(),
      );
      expect(opened, small);
      expect(sealed.sublist(0, 8), isNot(small.sublist(0, 8)));
    },
  );

  test('a reordered chunk fails to open', () async {
    final plain = Uint8List(ChatCrypto.attachmentChunkBytes * 2);
    plain[0] = 1;
    plain[ChatCrypto.attachmentChunkBytes] = 2;
    final key = crypto.newAttachmentKey();
    final prefix = crypto.newAttachmentNoncePrefix();
    addTearDown(key.dispose);
    final sealed = _concat(
      await crypto
          .sealAttachment(
            key: key,
            noncePrefix: prefix,
            input: Stream.fromIterable([plain]),
            totalBytes: plain.length,
          )
          .toList(),
    );
    final chunk = ChatCrypto.attachmentChunkBytes + 16;
    final swapped = Uint8List.fromList([
      ...sealed.sublist(chunk, chunk * 2),
      ...sealed.sublist(0, chunk),
    ]);

    expect(
      crypto
          .openAttachment(
            key: key,
            noncePrefix: prefix,
            input: Stream.fromIterable([swapped]),
            totalBytes: plain.length,
          )
          .toList(),
      throwsA(isA<SodiumException>()),
    );
  });

  test('a truncated ciphertext fails to open', () async {
    final plain = Uint8List(ChatCrypto.attachmentChunkBytes + 20);
    final key = crypto.newAttachmentKey();
    final prefix = crypto.newAttachmentNoncePrefix();
    addTearDown(key.dispose);
    final sealed = _concat(
      await crypto
          .sealAttachment(
            key: key,
            noncePrefix: prefix,
            input: Stream.fromIterable([plain]),
            totalBytes: plain.length,
          )
          .toList(),
    );

    Future<void> open(Uint8List bytes, int size) => crypto
        .openAttachment(
          key: key,
          noncePrefix: prefix,
          input: Stream.fromIterable([bytes]),
          totalBytes: size,
        )
        .toList();

    expect(
      open(Uint8List.sublistView(sealed, 0, sealed.length - 1), plain.length),
      throwsFormatException,
    );
    expect(
      open(
        Uint8List.sublistView(sealed, 0, ChatCrypto.attachmentChunkBytes + 16),
        plain.length,
      ),
      throwsFormatException,
    );
  });

  test('extra bytes and a lied size fail to open', () async {
    final plain = Uint8List.fromList(List.filled(30, 3));
    final key = crypto.newAttachmentKey();
    final prefix = crypto.newAttachmentNoncePrefix();
    addTearDown(key.dispose);
    final sealed = _concat(
      await crypto
          .sealAttachment(
            key: key,
            noncePrefix: prefix,
            input: Stream.fromIterable([plain]),
            totalBytes: plain.length,
          )
          .toList(),
    );

    expect(
      crypto
          .openAttachment(
            key: key,
            noncePrefix: prefix,
            input: Stream.fromIterable([
              [...sealed, 0],
            ]),
            totalBytes: plain.length,
          )
          .toList(),
      throwsFormatException,
    );
    expect(
      crypto
          .openAttachment(
            key: key,
            noncePrefix: prefix,
            input: Stream.fromIterable([sealed]),
            totalBytes: plain.length - 1,
          )
          .toList(),
      throwsA(isA<SodiumException>()),
    );
  });

  test('a flipped byte fails its tag', () async {
    final plain = Uint8List.fromList([9, 8, 7]);
    final key = crypto.newAttachmentKey();
    final prefix = crypto.newAttachmentNoncePrefix();
    addTearDown(key.dispose);
    final sealed = _concat(
      await crypto
          .sealAttachment(
            key: key,
            noncePrefix: prefix,
            input: Stream.fromIterable([plain]),
            totalBytes: plain.length,
          )
          .toList(),
    );
    sealed[0] ^= 0xff;

    expect(
      crypto
          .openAttachment(
            key: key,
            noncePrefix: prefix,
            input: Stream.fromIterable([sealed]),
            totalBytes: plain.length,
          )
          .toList(),
      throwsA(isA<SodiumException>()),
    );
  });

  test('the wrong key or nonce prefix fails the tag', () async {
    final plain = Uint8List.fromList([4, 5, 6, 7]);
    final key = crypto.newAttachmentKey();
    final other = crypto.newAttachmentKey();
    final prefix = crypto.newAttachmentNoncePrefix();
    final otherPrefix = crypto.newAttachmentNoncePrefix();
    addTearDown(key.dispose);
    addTearDown(other.dispose);
    final sealed = _concat(
      await crypto
          .sealAttachment(
            key: key,
            noncePrefix: prefix,
            input: Stream.fromIterable([plain]),
            totalBytes: plain.length,
          )
          .toList(),
    );

    expect(
      crypto
          .openAttachment(
            key: other,
            noncePrefix: prefix,
            input: Stream.fromIterable([sealed]),
            totalBytes: plain.length,
          )
          .toList(),
      throwsA(isA<SodiumException>()),
    );
    expect(
      crypto
          .openAttachment(
            key: key,
            noncePrefix: otherPrefix,
            input: Stream.fromIterable([sealed]),
            totalBytes: plain.length,
          )
          .toList(),
      throwsA(isA<SodiumException>()),
    );
  });

  test('a nonce prefix of the wrong length is refused', () async {
    final key = crypto.newAttachmentKey();
    addTearDown(key.dispose);
    expect(
      crypto
          .sealAttachment(
            key: key,
            noncePrefix: Uint8List(15),
            input: const Stream.empty(),
            totalBytes: 0,
          )
          .toList(),
      throwsFormatException,
    );
  });
}

/// Yields [plain] in uneven pieces, so a seal that only works on one buffer
/// fails this suite.
Stream<List<int>> _slices(Uint8List plain) async* {
  if (plain.isEmpty) return;
  final cuts = [1, 3, 64, 1000, ChatCrypto.attachmentChunkBytes - 1];
  var offset = 0;
  var cut = 0;
  while (offset < plain.length) {
    final n = cuts[cut % cuts.length];
    final end = offset + n > plain.length ? plain.length : offset + n;
    yield Uint8List.sublistView(plain, offset, end);
    offset = end;
    cut++;
  }
}

Uint8List _concat(List<Uint8List> parts) {
  final length = parts.fold<int>(0, (n, part) => n + part.length);
  final out = Uint8List(length);
  var offset = 0;
  for (final part in parts) {
    out.setRange(offset, offset + part.length, part);
    offset += part.length;
  }
  return out;
}
