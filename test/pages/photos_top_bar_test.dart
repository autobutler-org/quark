import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

// The real Photos page under the app-wide scope on a phone. Its bar used to
// carry six to eight buttons that scrolled sideways with no cue on a touch
// screen. The compact bar (#4150) holds the brand, Search and Select, and
// the account button, its dot on. At every phone width and at double text
// size, all of them are on screen whole, nothing overlaps, the page name is
// whole, and nothing scrolls.
//
// Not at 320px with double text: the page name alone needs most of the bar.
//
// The test font draws every glyph a full em wide, which makes "Paused" half as
// wide again as on a phone, so this lays the bar out in Roboto, Android's own
// font, from the Flutter SDK.
void main() {
  setUpAll(() async {
    final fonts =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    final roboto = FontLoader('Roboto');
    for (final weight in const ['Regular', 'Medium', 'Bold']) {
      roboto.addFont(
        File(
          '$fonts/Roboto-$weight.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await roboto.load();
  });

  const required = ['photos_search', 'photos_select', 'account_button'];

  Future<void> pumpPhotos(
    WidgetTester tester,
    double width,
    double textScale,
  ) async {
    final theme = QuarkTheme.dark(themeColor: QuarkThemeColor.classic);
    setViewport(tester, Size(width, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: QuarkAppBarTrailing(
          actions: [JobsBadge(runningCount: 3, onTap: () {})],
          compact: QuarkAccountButton(showDot: true, onPressed: () {}),
          child: const PhotosPage(),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  for (final (textScale, widths) in [
    (1.0, const [320.0, 360.0, 390.0, 412.0, 480.0]),
    (2.0, const [360.0, 390.0, 412.0, 480.0]),
  ]) {
    for (final width in widths) {
      testWidgets('photos top bar at ${width.toInt()}px, ${textScale}x text', (
        tester,
      ) async {
        await pumpPhotos(tester, width, textScale);
        expect(tester.takeException(), isNull);

        final appBar = find.byType(AppBar);
        final bar = tester.getRect(appBar);
        final label = find.descendant(
          of: appBar,
          matching: find.text('Photos'),
        );
        expect(label, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
          isFalse,
          reason: 'the page name is whole',
        );
        final brand = tester.getRect(
          find.descendant(of: appBar, matching: find.byType(QuarkBrandButton)),
        );
        expect(
          find.descendant(
            of: appBar,
            matching: find.byType(QuarkToolbarScroller),
          ),
          findsNothing,
          reason: 'a compact bar never scrolls',
        );
        expect(find.byKey(const ValueKey('jobs_badge')), findsNothing);
        expect(find.byKey(const ValueKey('refresh_button')), findsNothing);

        final rects = <String, Rect>{};
        for (final key in required) {
          final action = find.descendant(
            of: appBar,
            matching: find.byKey(ValueKey(key)),
          );
          expect(action, findsOneWidget, reason: key);
          final rect = tester.getRect(action);
          rects[key] = rect;
          expect(
            rect.left >= brand.right - 0.5 &&
                rect.right <= bar.right + 0.5 &&
                rect.top >= bar.top &&
                rect.bottom <= bar.top + kToolbarHeight + 0.5,
            isTrue,
            reason: '$key sits whole in the top row beside the brand: $rect',
          );
        }
        for (final a in rects.entries) {
          for (final b in rects.entries) {
            if (a.key.compareTo(b.key) < 0) {
              final overlap = a.value.intersect(b.value);
              expect(
                overlap.width > 0.5 && overlap.height > 0.5,
                isFalse,
                reason: '${a.key} overlaps ${b.key}',
              );
            }
          }
        }
        expect(
          rects['account_button']!.left,
          greaterThan(rects['photos_select']!.left),
          reason: 'the account button sits at the trailing edge',
        );
      });
    }
  }
}
