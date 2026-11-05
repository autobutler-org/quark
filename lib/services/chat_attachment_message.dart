import 'dart:convert';
import 'dart:typed_data';

import 'package:quark/services/chat_crypto.dart';
import 'package:quark/services/chat_messages_service.dart';
import 'package:quark/utils/chat_config.dart';
import 'package:sodium/sodium_sumo.dart';

/// The most bytes an attachment message's JSON may be before encryption.
///
/// [ChatCrypto.encrypt] adds a 24-byte nonce and a 16-byte tag, and the
/// Quark refuses a ciphertext past [ChatMessagesService.maxCiphertextBytes]
/// (16384). 16384 - 40 = 16344. A longer JSON is refused. The cap is not
/// raised.
const int chatAttachmentPlaintextMaxBytes =
    ChatMessagesService.maxCiphertextBytes - ChatConfig.ciphertextOverheadBytes;

/// Poly1305 tag appended to each sealed chunk. [ChatCrypto] keeps the
/// libsodium size private; the attachment format fixes it at 16 bytes.
const int _chunkTagBytes = 16;

final RegExp _attachmentIdPattern = RegExp(r'^[0-9a-f]{64}$');

/// One file to seal into a chat message (#2425).
///
/// [bytes] is the plaintext the caller already holds. Sealing reads it as
/// slices and does not copy it into a second buffer.
class AttachmentPlaintext {
  /// [name] and [mime] travel inside the message. [thumbnail], when set, is
  /// raw image bytes, not a second ciphertext: the message encryption covers
  /// it. It is dropped, longest first, when the JSON would pass
  /// [chatAttachmentPlaintextMaxBytes].
  const AttachmentPlaintext({
    required this.name,
    required this.mime,
    required this.bytes,
    this.thumbnail,
  });

  /// File name as the sender wants it shown.
  final String name;

  /// Media type, for example `image/jpeg`.
  final String mime;

  /// Plaintext bytes.
  final Uint8List bytes;

  /// Optional thumbnail. Omitted from the JSON when null or empty.
  final Uint8List? thumbnail;
}

/// What [prepareAttachmentMessage] returns, ready to upload and post.
class PreparedAttachmentMessage {
  /// [attachmentIds] and [sealedBytes] are in the same order.
  const PreparedAttachmentMessage({
    required this.ciphertext,
    required this.attachmentIds,
    required this.sealedBytes,
  });

  /// `nonce || ciphertext` of the JSON plaintext, under the channel key.
  final Uint8List ciphertext;

  /// Ids to send as `attachmentIds` on the post. Each is 64 lowercase hex
  /// characters.
  final List<String> attachmentIds;

  /// Sealed chunks of each file, concatenated, one buffer per id.
  final List<Uint8List> sealedBytes;
}

/// One file as a decrypted attachment message describes it.
class AttachmentDescriptor {
  /// [key] is 32 bytes and [nonce] is 16. [thumbnail] is null when the
  /// sender omitted it or it was dropped to fit the cap.
  const AttachmentDescriptor({
    required this.id,
    required this.key,
    required this.nonce,
    required this.name,
    required this.mime,
    required this.size,
    this.thumbnail,
  });

  /// 64 lowercase hex characters, chosen by the sender.
  final String id;

  /// File key. 32 bytes.
  final Uint8List key;

  /// Nonce prefix. 16 bytes. The chunk index is not stored.
  final Uint8List nonce;

  /// File name from the sender.
  final String name;

  /// Media type from the sender.
  final String mime;

  /// Plaintext size in bytes.
  final int size;

  /// Raw thumbnail bytes, or null.
  final Uint8List? thumbnail;
}

/// An attachment message after decryption, before its files are opened.
class DecodedAttachmentMessage {
  /// [text] is the caption, empty when the sender omitted it.
  const DecodedAttachmentMessage({
    required this.text,
    required this.attachments,
  });

  /// Caption. Empty when the JSON had no `text` field.
  final String text;

  /// Files in the order the JSON listed them.
  final List<AttachmentDescriptor> attachments;
}

/// One opened file: the descriptor from the message and its plaintext.
class OpenedAttachment {
  /// [bytes] is the plaintext [ChatCrypto.sealAttachment] was given.
  const OpenedAttachment({required this.descriptor, required this.bytes});

  /// Name, media type, size, and key the message carried.
  final AttachmentDescriptor descriptor;

  /// Plaintext.
  final Uint8List bytes;
}

/// A decrypted message. [attachments] is empty when it was ordinary text.
class OpenedAttachmentMessage {
  /// [text] is the whole message when [attachments] is empty and the
  /// plaintext was not attachment JSON, and the caption when it was.
  const OpenedAttachmentMessage({
    required this.text,
    required this.attachments,
  });

  /// Caption, or the text of a message that was not attachment JSON.
  final String text;

  /// Opened files. Empty for a text message.
  final List<OpenedAttachment> attachments;
}

/// A file sealed and described, before the JSON is built.
class _SealedFile {
  _SealedFile({
    required this.id,
    required this.key,
    required this.nonce,
    required this.name,
    required this.mime,
    required this.size,
    required this.thumbnail,
    required this.sealed,
  });

  final String id;
  final Uint8List key;
  final Uint8List nonce;
  final String name;
  final String mime;
  final int size;
  final Uint8List? thumbnail;
  final Uint8List sealed;
}

/// Seals [files] and encrypts the message that carries their keys (#2425).
///
/// Each file gets a random id, a file key, and a nonce prefix. The plaintext
/// is sealed with [ChatCrypto.sealAttachment]. The JSON is encrypted with
/// [ChatCrypto.encrypt] under [channelKey], bound to [channelId] and
/// [keyVersion] with [ChatCrypto.messageAad], the same as a text message.
///
/// [text] is omitted from the JSON when it is empty. Thumbnails are omitted
/// when absent, and dropped longest first while the JSON is over
/// [chatAttachmentPlaintextMaxBytes]. When it still does not fit, this throws
/// a [FormatException]. A message with no files is not this JSON: that throws
/// [ArgumentError], and the caller encrypts the text on its own.
///
/// File keys created here are disposed before this returns. [channelKey]
/// belongs to the caller.
Future<PreparedAttachmentMessage> prepareAttachmentMessage({
  required ChatCrypto crypto,
  required int channelId,
  required int keyVersion,
  required SecureKey channelKey,
  String text = '',
  required List<AttachmentPlaintext> files,
}) async {
  if (files.isEmpty) {
    throw ArgumentError.value(
      files,
      'files',
      'a message with no files is encrypted as text',
    );
  }
  final keys = <SecureKey>[];
  final sealed = <_SealedFile>[];
  try {
    for (final file in files) {
      final key = crypto.newAttachmentKey();
      keys.add(key);
      final nonce = crypto.newAttachmentNoncePrefix();
      final bytes = await _seal(crypto, key, nonce, file.bytes);
      sealed.add(
        _SealedFile(
          id: _newAttachmentId(crypto),
          key: key.extractBytes(),
          nonce: nonce,
          name: file.name,
          mime: file.mime,
          size: file.bytes.length,
          thumbnail: file.thumbnail,
          sealed: bytes,
        ),
      );
    }
    final plain = _encodeToFit(text, sealed);
    final Uint8List ciphertext;
    try {
      ciphertext = crypto.encrypt(
        plain,
        channelKey,
        additionalData: crypto.messageAad(
          channelId: channelId,
          keyVersion: keyVersion,
        ),
      );
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
    if (ciphertext.length > ChatMessagesService.maxCiphertextBytes) {
      throw FormatException(
        'This message is too large to send. It has to fit in '
        '$chatAttachmentPlaintextMaxBytes bytes.',
      );
    }
    return PreparedAttachmentMessage(
      ciphertext: ciphertext,
      attachmentIds: [for (final file in sealed) file.id],
      sealedBytes: [for (final file in sealed) file.sealed],
    );
  } finally {
    for (final file in sealed) {
      file.key.fillRange(0, file.key.length, 0);
      file.nonce.fillRange(0, file.nonce.length, 0);
    }
    for (final key in keys) {
      key.dispose();
    }
  }
}

/// Decrypts [ciphertext] and opens each file in [sealedBytes].
///
/// [sealedBytes] is in the same order as the message's attachments, one
/// buffer of sealed chunks per file. A plaintext that is not attachment JSON
/// comes back as [OpenedAttachmentMessage.text] with no files, which is how a
/// normal text message stays text.
///
/// The file keys are copied out of the message and disposed after each file
/// is opened. [channelKey] belongs to the caller.
Future<OpenedAttachmentMessage> openAttachmentMessage({
  required ChatCrypto crypto,
  required int channelId,
  required int keyVersion,
  required SecureKey channelKey,
  required Uint8List ciphertext,
  List<Uint8List> sealedBytes = const [],
}) async {
  final plain = crypto.decrypt(
    ciphertext,
    channelKey,
    additionalData: crypto.messageAad(
      channelId: channelId,
      keyVersion: keyVersion,
    ),
  );
  final decoded = decodeAttachmentMessage(plain);
  if (decoded == null) {
    return OpenedAttachmentMessage(
      text: utf8.decode(plain),
      attachments: const [],
    );
  }
  if (sealedBytes.length != decoded.attachments.length) {
    throw const FormatException('The sealed files do not match this message.');
  }
  final opened = <OpenedAttachment>[];
  for (var i = 0; i < decoded.attachments.length; i++) {
    final described = decoded.attachments[i];
    final key = crypto.sodium.secureCopy(described.key);
    try {
      opened.add(
        OpenedAttachment(
          descriptor: described,
          bytes: await _open(crypto, key, described, sealedBytes[i]),
        ),
      );
    } finally {
      key.dispose();
    }
  }
  return OpenedAttachmentMessage(text: decoded.text, attachments: opened);
}

/// Reads [plaintext] as an attachment message.
///
/// An object with `"v": 1` and `"attachments"` is that message. Anything
/// else, including other JSON, is a text message and this returns null. A
/// message that claims the shape but is malformed throws [FormatException].
DecodedAttachmentMessage? decodeAttachmentMessage(Uint8List plaintext) {
  final text = utf8.decode(plaintext);
  final Object? parsed;
  try {
    parsed = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (parsed is! Map<String, dynamic>) return null;
  if (parsed['v'] != 1 || !parsed.containsKey('attachments')) return null;
  return _readMessage(parsed);
}

DecodedAttachmentMessage _readMessage(Map<String, dynamic> json) {
  final text = json['text'];
  if (text != null && text is! String) {
    throw const FormatException('An attachment message caption must be text.');
  }
  final raw = json['attachments'];
  if (raw is! List) {
    throw const FormatException('An attachment message needs a list of files.');
  }
  return DecodedAttachmentMessage(
    text: text ?? '',
    attachments: [for (final item in raw) _readAttachment(item)],
  );
}

AttachmentDescriptor _readAttachment(Object? item) {
  if (item is! Map<String, dynamic>) {
    throw const FormatException('An attachment must be an object.');
  }
  final id = item['id'];
  if (id is! String || !_attachmentIdPattern.hasMatch(id)) {
    throw const FormatException(
      'An attachment id is 64 lowercase hex characters.',
    );
  }
  final name = item['name'];
  final mime = item['mime'];
  final size = item['size'];
  if (name is! String || mime is! String) {
    throw const FormatException('An attachment needs a name and a media type.');
  }
  if (size is! int || size < 0) {
    throw const FormatException('An attachment size is not valid.');
  }
  Uint8List? thumbnail;
  if (item.containsKey('thumbnail') && item['thumbnail'] != null) {
    thumbnail = _decodeBase64(
      item['thumbnail'],
      null,
      'An attachment thumbnail',
    );
  }
  return AttachmentDescriptor(
    id: id,
    key: _decodeBase64(item['key'], 32, 'An attachment key'),
    nonce: _decodeBase64(item['nonce'], 16, 'An attachment nonce'),
    name: name,
    mime: mime,
    size: size,
    thumbnail: thumbnail,
  );
}

Uint8List _decodeBase64(Object? value, int? length, String what) {
  if (value is! String) throw FormatException('$what is not valid.');
  final Uint8List bytes;
  try {
    bytes = base64Decode(value);
  } on FormatException {
    throw FormatException('$what is not valid.');
  }
  if (length != null && bytes.length != length) {
    throw FormatException('$what is not valid.');
  }
  return bytes;
}

String _newAttachmentId(ChatCrypto crypto) {
  final bytes = crypto.sodium.randombytes.buf(32);
  final hex = StringBuffer();
  for (final byte in bytes) {
    hex.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return hex.toString();
}

/// Views of [bytes], not copies. An empty file yields nothing.
Stream<List<int>> _byteSlices(Uint8List bytes) {
  if (bytes.isEmpty) return const Stream<List<int>>.empty();
  final size = ChatCrypto.attachmentChunkBytes;
  final slices = <Uint8List>[];
  for (var offset = 0; offset < bytes.length; offset += size) {
    final end = offset + size < bytes.length ? offset + size : bytes.length;
    slices.add(Uint8List.sublistView(bytes, offset, end));
  }
  return Stream.fromIterable(slices);
}

int _sealedLength(int totalBytes) {
  if (totalBytes == 0) return 0;
  final chunks =
      (totalBytes + ChatCrypto.attachmentChunkBytes - 1) ~/
      ChatCrypto.attachmentChunkBytes;
  return totalBytes + chunks * _chunkTagBytes;
}

Future<Uint8List> _seal(
  ChatCrypto crypto,
  SecureKey key,
  Uint8List nonce,
  Uint8List bytes,
) async {
  final out = Uint8List(_sealedLength(bytes.length));
  var offset = 0;
  await for (final part in crypto.sealAttachment(
    key: key,
    noncePrefix: nonce,
    input: _byteSlices(bytes),
    totalBytes: bytes.length,
  )) {
    final end = offset + part.length;
    if (end > out.length) {
      throw const FormatException('sealed attachment is longer than it claims');
    }
    out.setRange(offset, end, part);
    offset = end;
  }
  if (offset != out.length) {
    throw const FormatException('sealed attachment has the wrong length');
  }
  return out;
}

Future<Uint8List> _open(
  ChatCrypto crypto,
  SecureKey key,
  AttachmentDescriptor described,
  Uint8List sealed,
) async {
  final out = Uint8List(described.size);
  var offset = 0;
  await for (final part in crypto.openAttachment(
    key: key,
    noncePrefix: described.nonce,
    input: _byteSlices(sealed),
    totalBytes: described.size,
  )) {
    final end = offset + part.length;
    if (end > out.length) {
      throw const FormatException('attachment is longer than it claims');
    }
    out.setRange(offset, end, part);
    offset = end;
  }
  if (offset != out.length) {
    throw const FormatException('attachment truncated');
  }
  return out;
}

Uint8List _encodeToFit(String text, List<_SealedFile> files) {
  final dropped = <int>{};
  // A thumbnail whose base64 alone exceeds the cap can never be kept.
  // Drop those before encoding so a large image is not copied into the JSON.
  for (var i = 0; i < files.length; i++) {
    final thumb = files[i].thumbnail;
    if (thumb == null || thumb.isEmpty) continue;
    if (_base64Length(thumb.length) >= chatAttachmentPlaintextMaxBytes) {
      dropped.add(i);
    }
  }
  while (true) {
    final encoded = _encode(text, files, dropped);
    if (encoded.length <= chatAttachmentPlaintextMaxBytes) return encoded;
    final index = _longestThumbnail(files, dropped);
    if (index < 0) {
      encoded.fillRange(0, encoded.length, 0);
      throw FormatException(
        'This message is too large to send. It has to fit in '
        '$chatAttachmentPlaintextMaxBytes bytes.',
      );
    }
    encoded.fillRange(0, encoded.length, 0);
    dropped.add(index);
  }
}

int _base64Length(int n) => n == 0 ? 0 : 4 * ((n + 2) ~/ 3);

int _longestThumbnail(List<_SealedFile> files, Set<int> dropped) {
  var index = -1;
  var length = 0;
  for (var i = 0; i < files.length; i++) {
    if (dropped.contains(i)) continue;
    final thumb = files[i].thumbnail;
    if (thumb == null || thumb.isEmpty) continue;
    if (thumb.length > length) {
      length = thumb.length;
      index = i;
    }
  }
  return index;
}

Uint8List _encode(String text, List<_SealedFile> files, Set<int> dropped) =>
    utf8.encode(jsonEncode(_messageMap(text, files, dropped)));

Map<String, Object> _messageMap(
  String text,
  List<_SealedFile> files,
  Set<int> dropped,
) => {
  'v': 1,
  if (text.isNotEmpty) 'text': text,
  'attachments': [
    for (var i = 0; i < files.length; i++)
      _attachmentMap(files[i], dropped.contains(i)),
  ],
};

Map<String, Object> _attachmentMap(_SealedFile file, bool dropThumbnail) {
  final map = <String, Object>{
    'id': file.id,
    'key': base64Encode(file.key),
    'nonce': base64Encode(file.nonce),
    'name': file.name,
    'mime': file.mime,
    'size': file.size,
  };
  final thumb = file.thumbnail;
  if (!dropThumbnail && thumb != null && thumb.isNotEmpty) {
    map['thumbnail'] = base64Encode(thumb);
  }
  return map;
}
