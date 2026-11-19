import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _albums = [
  SlideshowMusicOption(id: 'k1', title: 'Blue', subtitle: 'Joni Mitchell'),
  SlideshowMusicOption(id: 'k2', title: 'Kind of Blue'),
];

void main() {
  testBothViewports('lists "No music" and every album, the playing one '
      'checked', (tester, size) async {
    await pumpAt(
      tester,
      SlideshowMusicPicker(
        options: _albums,
        selectedId: 'k2',
        onSelected: (_) {},
      ),
      size: size,
    );

    expect(find.byKey(const ValueKey('slideshow_music_none')), findsOneWidget);
    expect(find.text('Blue'), findsOneWidget);
    expect(find.text('Joni Mitchell'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('slideshow_music_option_k2')),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports the album picked, and null for "No music"', (
    tester,
  ) async {
    final picked = <String?>[];
    await pumpAt(
      tester,
      SlideshowMusicPicker(options: _albums, onSelected: picked.add),
    );

    await tester.tap(find.byKey(const ValueKey('slideshow_music_option_k1')));
    await tester.tap(find.byKey(const ValueKey('slideshow_music_none')));

    expect(picked, ['k1', null]);
  });

  testWidgets('shows a loader while loading and the error when it failed', (
    tester,
  ) async {
    await pumpAt(
      tester,
      SlideshowMusicPicker(
        options: const [],
        isLoading: true,
        onSelected: (_) {},
      ),
    );
    expect(find.byType(QuarkLoader), findsOneWidget);

    await pumpAt(
      tester,
      SlideshowMusicPicker(
        options: const [],
        error: "Couldn't load your music.",
        onSelected: (_) {},
      ),
    );
    expect(find.text("Couldn't load your music."), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
  });
}
