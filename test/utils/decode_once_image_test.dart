import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/decode_once_image.dart';

/// A completer the test drives by hand.
class _Completer extends ImageStreamCompleter {
  int listeners = 0;

  void emit(ImageInfo image) => setImage(image);

  void fail(Object error) =>
      reportError(exception: error, stack: StackTrace.empty, silent: true);

  @override
  void addListener(ImageStreamListener listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(ImageStreamListener listener) {
    listeners--;
    super.removeListener(listener);
  }
}

/// Hands out [completer] for every load and counts the loads.
class _Provider extends ImageProvider<_Provider> {
  _Provider(this.completer);

  final _Completer completer;
  var loads = 0;

  @override
  Future<_Provider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_Provider key, ImageDecoderCallback decode) {
    loads++;
    return completer;
  }
}

Future<ui.Image> _image() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xFF00FF00), ui.BlendMode.src);
  return recorder.endRecording().toImage(2, 2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(
    () => imageCache
      ..clear()
      ..clearLiveImages(),
  );

  test('a listener coming back gets the picture already decoded', () async {
    final inner = _Completer();
    final image = DecodeOnceImage(_Provider(inner));
    final stream = image.resolve(ImageConfiguration.empty);
    final seen = <ImageInfo>[];
    final listener = ImageStreamListener((info, _) => seen.add(info));
    stream.addListener(listener);
    inner.emit(ImageInfo(image: await _image()));
    stream.removeListener(listener);

    // The tile comes back while the cache still holds the picture.
    final again = image.resolve(ImageConfiguration.empty);
    again.addListener(listener);

    expect(inner.listeners, 1, reason: 'the inner completer never re-listens');
    expect(seen, hasLength(2));
    expect(seen.last.image.isCloneOf(seen.first.image), isTrue);
    again.removeListener(listener);
    for (final info in seen) {
      info.dispose();
    }
  });

  test('a failed load is evicted, so the next one starts afresh', () async {
    final inner = _Completer();
    final provider = _Provider(inner);
    final image = DecodeOnceImage(provider);
    final errors = <Object>[];
    image
        .resolve(ImageConfiguration.empty)
        .addListener(
          ImageStreamListener((_, _) {}, onError: (e, _) => errors.add(e)),
        );
    inner.fail(StateError('503'));
    await Future<void>.delayed(Duration.zero);

    expect(errors, hasLength(1));
    final key = await image.obtainKey(ImageConfiguration.empty);
    expect(imageCache.statusForKey(key).untracked, isTrue);
    image.resolve(ImageConfiguration.empty);
    expect(provider.loads, 2);
  });

  testWidgets('evicting it lets go of the inner completer', (tester) async {
    final inner = _Completer();
    final image = DecodeOnceImage(_Provider(inner));
    final stream = image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) => info.dispose());
    stream.addListener(listener);
    inner.emit(ImageInfo(image: (await tester.runAsync(_image))!));
    stream.removeListener(listener);
    expect(inner.listeners, 1);

    await image.evict();
    // The image cache lets go of what it evicts after the next frame.
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(inner.listeners, 0);
  });
}
