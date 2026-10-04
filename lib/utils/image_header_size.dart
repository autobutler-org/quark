import 'dart:math' as math;
import 'dart:typed_data';

/// How many leading bytes of a picture [imageHeaderSize] needs at most:
/// enough to get past a JPEG's EXIF block, thumbnail included, to its frame
/// header.
const imageHeadLimit = 256 * 1024;

/// The pixel size of the picture whose first bytes are [head], read from its
/// header alone, or null when [head] is not a PNG, JPEG, GIF, WebP or BMP or
/// is cut off before the size.
///
/// Nothing is decoded: the size is read from the few bytes each format puts
/// it in, so a picture of any size costs at most [imageHeadLimit] of memory.
/// A JPEG whose EXIF orientation turns it on its side (5 to 8) reports its
/// width and height swapped, as it is drawn.
({int width, int height})? imageHeaderSize(List<int> head) {
  final bytes = head is Uint8List ? head : Uint8List.fromList(head);
  final data = ByteData.sublistView(bytes);
  final size =
      _png(bytes, data) ??
      _gif(bytes, data) ??
      _jpeg(bytes, data) ??
      _webp(bytes, data) ??
      _bmp(bytes, data);
  if (size == null || size.width <= 0 || size.height <= 0) return null;
  return size;
}

bool _startsWith(Uint8List bytes, List<int> prefix, [int at = 0]) {
  if (bytes.length < at + prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[at + i] != prefix[i]) return false;
  }
  return true;
}

({int width, int height})? _png(Uint8List bytes, ByteData data) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (!_startsWith(bytes, signature) || bytes.length < 24) return null;
  return (width: data.getUint32(16), height: data.getUint32(20));
}

({int width, int height})? _gif(Uint8List bytes, ByteData data) {
  if (!_startsWith(bytes, 'GIF8'.codeUnits) || bytes.length < 10) return null;
  return (
    width: data.getUint16(6, Endian.little),
    height: data.getUint16(8, Endian.little),
  );
}

({int width, int height})? _jpeg(Uint8List bytes, ByteData data) {
  if (!_startsWith(bytes, const [0xFF, 0xD8])) return null;
  var sideways = false;
  var at = 2;
  while (at + 4 <= bytes.length) {
    if (bytes[at] != 0xFF) return null;
    final marker = bytes[at + 1];
    if (marker == 0xFF) {
      at++; // fill byte
      continue;
    }
    final length = data.getUint16(at + 2);
    final body = at + 4;
    final isFrame =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isFrame) {
      if (body + 5 > bytes.length) return null;
      final height = data.getUint16(body + 1);
      final width = data.getUint16(body + 3);
      return sideways
          ? (width: height, height: width)
          : (width: width, height: height);
    }
    if (marker == 0xDA || marker == 0xD9) return null; // image data, end
    if (marker == 0xE1) {
      final end = math.min(at + 2 + length, bytes.length);
      final orientation = _exifOrientation(bytes, body, end);
      if (orientation != null) sideways = orientation >= 5 && orientation <= 8;
    }
    at += 2 + length;
  }
  return null;
}

/// The Orientation tag of the EXIF block in `bytes[start, end)`, if any.
int? _exifOrientation(Uint8List bytes, int start, int end) {
  if (!_startsWith(bytes, const [0x45, 0x78, 0x69, 0x66, 0, 0], start)) {
    return null;
  }
  final tiff = start + 6;
  if (tiff + 8 > end) return null;
  final Endian endian;
  if (_startsWith(bytes, 'II'.codeUnits, tiff)) {
    endian = Endian.little;
  } else if (_startsWith(bytes, 'MM'.codeUnits, tiff)) {
    endian = Endian.big;
  } else {
    return null;
  }
  final data = ByteData.sublistView(bytes, tiff, end);
  final ifd = data.getUint32(4, endian);
  if (ifd + 2 > data.lengthInBytes) return null;
  final count = data.getUint16(ifd, endian);
  for (var i = 0; i < count; i++) {
    final entry = ifd + 2 + i * 12;
    if (entry + 12 > data.lengthInBytes) return null;
    if (data.getUint16(entry, endian) == 0x0112) {
      return data.getUint16(entry + 8, endian);
    }
  }
  return null;
}

({int width, int height})? _webp(Uint8List bytes, ByteData data) {
  if (!_startsWith(bytes, 'RIFF'.codeUnits) ||
      !_startsWith(bytes, 'WEBP'.codeUnits, 8)) {
    return null;
  }
  int u24(int at) => bytes[at] | bytes[at + 1] << 8 | bytes[at + 2] << 16;
  if (_startsWith(bytes, 'VP8 '.codeUnits, 12) && bytes.length >= 30) {
    return (
      width: data.getUint16(26, Endian.little) & 0x3FFF,
      height: data.getUint16(28, Endian.little) & 0x3FFF,
    );
  }
  if (_startsWith(bytes, 'VP8L'.codeUnits, 12) && bytes.length >= 25) {
    final bits = data.getUint32(21, Endian.little);
    return (width: (bits & 0x3FFF) + 1, height: ((bits >> 14) & 0x3FFF) + 1);
  }
  if (_startsWith(bytes, 'VP8X'.codeUnits, 12) && bytes.length >= 30) {
    return (width: u24(24) + 1, height: u24(27) + 1);
  }
  return null;
}

({int width, int height})? _bmp(Uint8List bytes, ByteData data) {
  if (!_startsWith(bytes, 'BM'.codeUnits) || bytes.length < 26) return null;
  return (
    width: data.getInt32(18, Endian.little).abs(),
    height: data.getInt32(22, Endian.little).abs(),
  );
}

/// Keeps the first [limit] bytes of a byte stream as it passes through, so a
/// picture can be uploaded as a stream and still have its size read with
/// [imageHeaderSize] once it is sent — without reading the file twice or
/// holding more than [limit] bytes of it.
class ImageHeadRecorder {
  /// Records up to [limit] bytes; [imageHeadLimit] by default.
  ImageHeadRecorder({this.limit = imageHeadLimit});

  /// The most bytes kept.
  final int limit;

  final _head = BytesBuilder(copy: true);

  /// The bytes recorded so far.
  Uint8List get head => _head.toBytes();

  /// [source], unchanged, recording its first [limit] bytes as it is read.
  Stream<List<int>> watch(Stream<List<int>> source) => source.map((chunk) {
    final room = limit - _head.length;
    if (room > 0) {
      _head.add(chunk.length <= room ? chunk : chunk.sublist(0, room));
    }
    return chunk;
  });
}
