import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/client_thumbnail_config.dart';

void main() {
  group('scaledToLongEdge', () {
    test('scales the long edge down and keeps the aspect ratio', () {
      expect(scaledToLongEdge(4032, 3024, 400), (width: 400, height: 300));
      expect(scaledToLongEdge(1080, 1920, 400), (width: 225, height: 400));
    });

    test('never enlarges a small image', () {
      expect(scaledToLongEdge(320, 240, 400), (width: 320, height: 240));
    });

    test('keeps a sliver at least one pixel wide', () {
      expect(scaledToLongEdge(10000, 3, 400), (width: 400, height: 1));
    });
  });

  group('videoFrameTime', () {
    test('is two seconds into a long video', () {
      expect(
        videoFrameTime(const Duration(minutes: 3)),
        const Duration(seconds: 2),
      );
      expect(
        videoFrameTime(const Duration(seconds: 20)),
        const Duration(seconds: 2),
      );
    });

    test('is a tenth of the way into a short clip', () {
      expect(
        videoFrameTime(const Duration(seconds: 5)),
        const Duration(milliseconds: 500),
      );
      expect(videoFrameTime(Duration.zero), Duration.zero);
    });
  });

  test('photos and videos get thumbnails, documents do not', () {
    expect(wantsClientThumbnail('photo.jpg'), isTrue);
    expect(wantsClientThumbnail('IMG_1.HEIC'), isTrue);
    expect(wantsClientThumbnail('clip.mp4'), isTrue);
    expect(wantsClientThumbnail('notes.txt'), isFalse);
  });

  test('videos and HEIC are the files only a client renders', () {
    expect(needsClientRender('clip.MP4'), isTrue);
    expect(needsClientRender('IMG_1.HEIC'), isTrue);
    expect(needsClientRender('a.heif'), isTrue);
    expect(needsClientRender('a.jpg'), isFalse);
    expect(needsClientRender('scan.dng'), isFalse);
  });
}
