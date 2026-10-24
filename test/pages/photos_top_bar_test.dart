import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/models/app_notification.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/widgets/layout/connection_sheet_button.dart';
import 'package:quark/widgets/notifications/notifications_bell.dart';
import 'package:quark/widgets/photos/photos_bar_bottom.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

// The real Photos page under the real app-wide controls, at its most crowded:
// the device paused (a labeled chip), jobs running and a three-digit
// notification count. On a phone the page's actions used to paint over the
// brand and hide its name. At every width and at double text size, nothing in
// the bar overlaps, the page name is whole, every badge stays inside the bar,
// and every action is on screen or can be dragged on screen.
//
// Not at 320px with double text: the page name, the Paused chip and one page
// action need more than the bar has there, so the chip cannot show whole.
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

  const required = [
    'photos_select',
    'connection_indicator',
    'jobs_badge',
    'notifications_bell',
  ];

  NotificationsController notifications(int count) {
    final served = [
      for (var i = 0; i < count; i++)
        AppNotification(type: NotificationType.backupDue, link: '/$i'),
    ];
    final controller = NotificationsController(
      listNotifications: () async => served,
      readDisabled: () async => {},
      saveEnabled: (_, _) async => {},
      events: () => const Stream<FileEvent>.empty(),
      session: () => ValueNotifier('token'),
    )..start();
    addTearDown(controller.dispose);
    return controller;
  }

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
          actions: [
            ConnectionSheetButton(
              mode: ConnectionMode.local,
              paused: true,
              onNavigate: (_) {},
            ),
            JobsBadge(runningCount: 3, onTap: () {}),
            NotificationsBell(
              controller: notifications(120),
              onNavigate: (_) {},
            ),
          ],
          child: const PhotosPage(),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder inBar(Finder finder) =>
      find.descendant(of: find.byType(AppBar), matching: finder);

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

        final bar = tester.getRect(find.byType(AppBar));
        final label = inBar(find.text('Photos'));
        expect(label, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
          isFalse,
          reason: 'the page name is whole',
        );
        final brand = tester.getRect(inBar(find.byType(QuarkBrandButton)));

        final topRow = find.descendant(
          of: find.byType(QuarkToolbarScroller),
          matching: find.byWidgetPredicate(
            (widget) => widget is QuarkBarIconButton || widget is QuarkBarChip,
          ),
        );
        final bottom = find.byType(PhotosBarBottom);
        final keys = [
          for (final element in inBar(topRow).evaluate())
            if (find
                .descendant(of: bottom, matching: find.byWidget(element.widget))
                .evaluate()
                .isEmpty)
              (element.widget.key! as ValueKey<String>).value,
        ];
        expect(keys, containsAll(required));
        Finder action(String key) => inBar(find.byKey(ValueKey(key)));
        Finder scrollerOf(String key) => find.ancestor(
          of: action(key),
          matching: find.byType(QuarkToolbarScroller),
        );
        bool visible(String key) {
          final rect = tester.getRect(action(key));
          final viewport = tester.getRect(scrollerOf(key));
          return rect.left >= viewport.left - 0.5 &&
              rect.right <= viewport.right + 0.5 &&
              rect.left >= brand.right &&
              rect.right <= bar.right + 0.5;
        }

        for (final (key, count) in [
          ('jobs_badge', '3'),
          ('notifications_bell', '120'),
        ]) {
          final badge = tester.getRect(
            find.descendant(of: action(key), matching: find.text(count)),
          );
          final button = tester.getRect(action(key));
          expect(
            button.contains(badge.topLeft) &&
                button.contains(badge.bottomRight),
            isTrue,
            reason: 'the $count badge stays inside $key: $badge in $button',
          );
        }

        final unseen = <String>{};
        final rects = <String, Rect>{};
        for (final key in keys) {
          expect(action(key), findsOneWidget, reason: key);
          final rect = tester.getRect(action(key));
          rects[key] = rect;
          expect(
            rect.top >= bar.top && rect.bottom <= bar.bottom,
            isTrue,
            reason: '$key fits the bar height',
          );
          if (!visible(key)) unseen.add(key);
        }

        final shown = rects.entries.where((e) => !unseen.contains(e.key));
        for (final a in shown) {
          expect(a.value.overlaps(brand), isFalse, reason: '${a.key} on brand');
          for (final b in shown) {
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

        for (final key in [...unseen]) {
          for (var step = 0; step < 40 && !visible(key); step++) {
            await tester.drag(scrollerOf(key), const Offset(-24, 0));
            await tester.pump();
          }
          if (visible(key)) unseen.remove(key);
        }
        expect(unseen, isEmpty, reason: 'dragging brings every action in');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
