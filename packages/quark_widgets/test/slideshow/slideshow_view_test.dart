import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// A 1x1 transparent PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// What the view called back with.
class _Calls {
  final log = <String>[];
}

SlideshowView _view(
  _Calls calls, {
  String slideId = 'a',
  bool controlsVisible = true,
  bool isPlaying = true,
  bool shuffle = false,
  int intervalSeconds = 5,
  bool withMusic = true,
  String? musicTitle,
  String? error,
}) => SlideshowView(
  image: MemoryImage(_png),
  slideId: slideId,
  isPlaying: isPlaying,
  intervalSeconds: intervalSeconds,
  shuffle: shuffle,
  position: 2,
  count: 12,
  controlsVisible: controlsVisible,
  error: error,
  musicTitle: musicTitle,
  onActivity: () => calls.log.add('activity'),
  onPlayPause: () => calls.log.add('playPause'),
  onPrevious: () => calls.log.add('previous'),
  onNext: () => calls.log.add('next'),
  onIntervalChanged: (s) => calls.log.add('interval:$s'),
  onShuffleChanged: (on) => calls.log.add('shuffle:$on'),
  onMusic: withMusic ? () => calls.log.add('music') : null,
  onExit: () => calls.log.add('exit'),
);

void main() {
  testBothViewports('shows every control without overflowing', (
    tester,
    size,
  ) async {
    await pumpAt(tester, _view(_Calls()), size: size);

    for (final key in [
      'slideshow_exit',
      'slideshow_previous',
      'slideshow_play_pause',
      'slideshow_next',
      'slideshow_interval',
      'slideshow_shuffle',
      'slideshow_music',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    expect(find.text('3 / 12'), findsOneWidget);
    expect(find.byKey(const ValueKey('slideshow_slide_a')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('shows the photo whole, never cropped', (
    tester,
    size,
  ) async {
    await pumpAt(tester, _view(_Calls()), size: size);

    final image = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('slideshow_slide_a')),
        matching: find.byType(Image),
      ),
    );
    expect(image.fit, BoxFit.contain);
  });

  testWidgets('each control calls back', (tester) async {
    final calls = _Calls();
    await pumpAt(tester, _view(calls));

    for (final key in [
      'slideshow_previous',
      'slideshow_play_pause',
      'slideshow_next',
      'slideshow_interval',
      'slideshow_shuffle',
      'slideshow_music',
      'slideshow_exit',
    ]) {
      await tester.tap(find.byKey(ValueKey(key)));
    }

    expect(calls.log, [
      'previous',
      'playPause',
      'next',
      'interval:10',
      'shuffle:true',
      'music',
      'exit',
    ]);
  });

  testWidgets('the interval steps through the choices and wraps around', (
    tester,
  ) async {
    final calls = _Calls();
    await pumpAt(tester, _view(calls, intervalSeconds: 15));

    expect(find.text('15s'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('slideshow_interval')));

    expect(calls.log, ['interval:3']);
  });

  testWidgets('paused, the button offers play', (tester) async {
    await pumpAt(tester, _view(_Calls(), isPlaying: false));

    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsNothing);
  });

  testWidgets('no music library leaves the music button out', (tester) async {
    await pumpAt(tester, _view(_Calls(), withMusic: false));

    expect(find.byKey(const ValueKey('slideshow_music')), findsNothing);
  });

  testWidgets('hidden controls take no taps; a tap shows them', (tester) async {
    final calls = _Calls();
    await pumpAt(tester, _view(calls, controlsVisible: false));

    await tester.tap(
      find.byKey(const ValueKey('slideshow_exit')),
      warnIfMissed: false,
    );

    expect(calls.log, ['activity']);
  });

  testWidgets('an error shows in place of the photo', (tester) async {
    await pumpAt(tester, _view(_Calls(), error: "Couldn't load the photo."));

    expect(find.text("Couldn't load the photo."), findsOneWidget);
    expect(find.byKey(const ValueKey('slideshow_slide_a')), findsNothing);
  });

  group('changing photo', () {
    Future<void> pumpSlide(
      WidgetTester tester,
      String id, {
      required bool reduceMotion,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(
          QuarkThemeColor.classic.tokensFor(Brightness.dark),
          Brightness.dark,
        ),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(body: _view(_Calls(), slideId: id)),
        ),
      ),
    );

    testWidgets('cross-fades with motion allowed', (tester) async {
      await pumpSlide(tester, 'a', reduceMotion: false);
      await pumpSlide(tester, 'b', reduceMotion: false);
      await tester.pump(const Duration(milliseconds: 100));

      // Both photos are on screen mid-fade.
      expect(find.byKey(const ValueKey('slideshow_slide_a')), findsOneWidget);
      expect(find.byKey(const ValueKey('slideshow_slide_b')), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('slideshow_slide_a')), findsNothing);
    });

    testWidgets('changes at once under reduced motion', (tester) async {
      await pumpSlide(tester, 'a', reduceMotion: true);
      await pumpSlide(tester, 'b', reduceMotion: true);
      await tester.pump();

      expect(find.byKey(const ValueKey('slideshow_slide_a')), findsNothing);
      expect(find.byKey(const ValueKey('slideshow_slide_b')), findsOneWidget);
    });
  });
}
