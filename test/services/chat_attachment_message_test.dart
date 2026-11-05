import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/chat_poll.dart';
import 'package:quark/services/chat_attachment_message.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/chat_messages_service.dart';
import 'package:quark/utils/chat_config.dart';
import 'package:sodium/sodium.dart';

/// Real libsodium, same as [chat_attachment_crypto_test.dart].
void main() {
  late ChatCrypto crypto;

  setUpAll(() async => crypto = await ChatCrypto.load());

  const channelId = 9;
  const keyVersion = 3;

  SecureKey channelKey() {
    final key = crypto.newChannelKey();
    addTearDown(key.dispose);
    return key;
  }

  Uint8List decrypt(Uint8List ciphertext, SecureKey key) => crypto.decrypt(
    ciphertext,
    key,
    additionalData: crypto.messageAad(
      channelId: channelId,
      keyVersion: keyVersion,
    ),
  );

  test('a text message still decrypts as text', () async {
    final key = channelKey();
    const text = 'hello from chat';
    final ciphertext = crypto.encrypt(
      Uint8List.fromList(utf8.encode(text)),
      key,
      additionalData: crypto.messageAad(channelId: 4, keyVersion: 1),
    );
    final plain = crypto.decrypt(
      ciphertext,
      key,
      additionalData: crypto.messageAad(channelId: 4, keyVersion: 1),
    );

    expect(utf8.decode(plain), text);
    expect(decodeAttachmentMessage(plain), isNull);
    expect(
      decodeAttachmentMessage(
        Uint8List.fromList(utf8.encode('{"v":1,"text":"no files"}')),
      ),
      isNull,
    );

    final opened = await openAttachmentMessage(
      crypto: crypto,
      channelId: 4,
      keyVersion: 1,
      channelKey: key,
      ciphertext: ciphertext,
    );
    expect(opened.text, text);
    expect(opened.attachments, isEmpty);
  });

  test('a small file round-trips through the message', () async {
    final key = channelKey();
    final plain = Uint8List.fromList([1, 2, 3, 4, 5]);
    final thumbnail = Uint8List.fromList([9, 8, 7]);
    final prepared = await prepareAttachmentMessage(
      crypto: crypto,
      channelId: channelId,
      keyVersion: keyVersion,
      channelKey: key,
      text: 'see attached',
      files: [
        AttachmentPlaintext(
          name: 'photo.jpg',
          mime: 'image/jpeg',
          bytes: plain,
          thumbnail: thumbnail,
        ),
      ],
    );

    expect(prepared.attachmentIds.single, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(prepared.sealedBytes.single, isNot(plain));

    final message = decrypt(prepared.ciphertext, key);
    expect(message.length, lessThanOrEqualTo(chatAttachmentPlaintextMaxBytes));
    expect(
      prepared.ciphertext.length,
      message.length + ChatConfig.ciphertextOverheadBytes,
    );
    final decoded = decodeAttachmentMessage(message);
    expect(decoded, isNotNull);
    final described = decoded!.attachments.single;
    expect(decoded.text, 'see attached');
    expect(described.name, 'photo.jpg');
    expect(described.mime, 'image/jpeg');
    expect(described.size, plain.length);
    expect(described.key, hasLength(32));
    expect(described.nonce, hasLength(16));
    expect(described.thumbnail, thumbnail);
    expect(described.id, prepared.attachmentIds.single);

    final opened = await openAttachmentMessage(
      crypto: crypto,
      channelId: channelId,
      keyVersion: keyVersion,
      channelKey: key,
      ciphertext: prepared.ciphertext,
      sealedBytes: prepared.sealedBytes,
    );
    expect(opened.text, 'see attached');
    expect(opened.attachments.single.bytes, plain);
    expect(opened.attachments.single.descriptor.key, described.key);
  });

  test('a swapped chunk fails to open', () async {
    final key = channelKey();
    final plain = Uint8List(ChatCrypto.attachmentChunkBytes * 2);
    plain[0] = 1;
    plain[ChatCrypto.attachmentChunkBytes] = 2;
    final prepared = await prepareAttachmentMessage(
      crypto: crypto,
      channelId: channelId,
      keyVersion: keyVersion,
      channelKey: key,
      files: [
        AttachmentPlaintext(
          name: 'two.bin',
          mime: 'application/octet-stream',
          bytes: plain,
        ),
      ],
    );
    final described = decodeAttachmentMessage(
      decrypt(prepared.ciphertext, key),
    )!.attachments.single;
    final sealed = prepared.sealedBytes.single;
    final chunk = ChatCrypto.attachmentChunkBytes + 16;
    final swapped = Uint8List.fromList([
      ...sealed.sublist(chunk, chunk * 2),
      ...sealed.sublist(0, chunk),
    ]);
    final fileKey = crypto.sodium.secureCopy(described.key);
    addTearDown(fileKey.dispose);

    expect(
      crypto
          .openAttachment(
            key: fileKey,
            noncePrefix: described.nonce,
            input: Stream.fromIterable([swapped]),
            totalBytes: described.size,
          )
          .toList(),
      throwsA(isA<SodiumException>()),
    );
  });

  test('a thumbnail that would pass 16344 bytes is dropped', () async {
    expect(chatAttachmentPlaintextMaxBytes, 16344);
    expect(
      chatAttachmentPlaintextMaxBytes,
      ChatMessagesService.maxCiphertextBytes -
          ChatConfig.ciphertextOverheadBytes,
    );

    final key = channelKey();
    // Base64 of this thumbnail is just under the cap, and the JSON around it
    // pushes the plaintext over, so it has to be dropped rather than refused.
    final tooBig = Uint8List(12255);
    tooBig[0] = 1;
    final small = Uint8List.fromList([4, 5, 6, 7]);
    final prepared = await prepareAttachmentMessage(
      crypto: crypto,
      channelId: channelId,
      keyVersion: keyVersion,
      channelKey: key,
      files: [
        AttachmentPlaintext(
          name: 'wide.bin',
          mime: 'application/octet-stream',
          bytes: Uint8List.fromList([1]),
          thumbnail: tooBig,
        ),
        AttachmentPlaintext(
          name: 'tiny.bin',
          mime: 'image/png',
          bytes: Uint8List.fromList([2, 3]),
          thumbnail: small,
        ),
      ],
    );

    final message = decrypt(prepared.ciphertext, key);
    expect(message.length, lessThanOrEqualTo(16344));
    expect(message.length, lessThanOrEqualTo(chatAttachmentPlaintextMaxBytes));
    expect(
      prepared.ciphertext.length,
      lessThanOrEqualTo(ChatMessagesService.maxCiphertextBytes),
    );
    expect(
      prepared.ciphertext.length,
      message.length + ChatConfig.ciphertextOverheadBytes,
    );
    final parsed = jsonDecode(utf8.decode(message)) as Map<String, dynamic>;
    expect(parsed.containsKey('text'), isFalse);
    expect(parsed['v'], 1);

    final decoded = decodeAttachmentMessage(message)!;
    expect(decoded.text, isEmpty);
    expect(decoded.attachments[0].thumbnail, isNull);
    expect(decoded.attachments[0].name, 'wide.bin');
    expect(decoded.attachments[1].thumbnail, small);
    expect(decoded.attachments[1].name, 'tiny.bin');

    final opened = await openAttachmentMessage(
      crypto: crypto,
      channelId: channelId,
      keyVersion: keyVersion,
      channelKey: key,
      ciphertext: prepared.ciphertext,
      sealedBytes: prepared.sealedBytes,
    );
    expect(opened.attachments[0].bytes, [1]);
    expect(opened.attachments[1].bytes, [2, 3]);
  });

  test('a message that still does not fit is refused', () async {
    final key = channelKey();
    expect(
      prepareAttachmentMessage(
        crypto: crypto,
        channelId: channelId,
        keyVersion: keyVersion,
        channelKey: key,
        text: 'a' * 20000,
        files: [
          AttachmentPlaintext(
            name: 'a.bin',
            mime: 'application/octet-stream',
            bytes: Uint8List.fromList([1]),
          ),
        ],
      ),
      throwsFormatException,
    );
  });

  test('postMessage JSON includes attachmentIds when they are passed', () {
    final id = 'ab' * 32;
    final ciphertext = Uint8List.fromList([1, 2, 3, 4]);
    final body = ChatMessagesService.postMessageBody(
      keyVersion: 2,
      ciphertext: ciphertext,
      clientMessageId: 'send-1',
      attachmentIds: [id],
      poll: const ChatPoll(allowChange: true),
    );

    expect(body['keyVersion'], 2);
    expect(body['ciphertext'], base64Encode(ciphertext));
    expect(body['clientMessageId'], 'send-1');
    expect(body['attachmentIds'], [id]);
    expect(body['poll'], {
      'allowChange': true,
      'anonymous': false,
      'resultsAfterClose': false,
    });
    expect(jsonEncode(body), contains('"attachmentIds"'));

    final plain = ChatMessagesService.postMessageBody(
      keyVersion: 2,
      ciphertext: ciphertext,
    );
    expect(plain.containsKey('attachmentIds'), isFalse);
    expect(plain.containsKey('clientMessageId'), isFalse);
    expect(plain.containsKey('poll'), isFalse);
    expect(jsonEncode(plain), isNot(contains('attachmentIds')));
  });
}
