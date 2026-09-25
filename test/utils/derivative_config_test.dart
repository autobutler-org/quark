import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/derivative_config.dart';

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

  test('HEIC and video get a display preview, other photos do not', () {
    expect(wantsDisplayPreview('IMG_0001.HEIC'), isTrue);
    expect(wantsDisplayPreview('clip.heif'), isTrue);
    expect(wantsDisplayPreview('clip.mov'), isTrue);
    expect(wantsDisplayPreview('photo.jpg'), isFalse);
  });

  test('photos and videos get derivatives, documents do not', () {
    expect(wantsDerivatives('photo.jpg'), isTrue);
    expect(wantsDerivatives('clip.mp4'), isTrue);
    expect(wantsDerivatives('notes.txt'), isFalse);
  });
}
