import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/notifications_controller.dart';
import 'package:quark/models/app_notification.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/widgets/layout/connection_sheet_button.dart';
import 'package:quark/widgets/notifications/notifications_bell.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/file_top_bar.dart';
import '../../../support/tap_target_guidelines.dart' show setViewport;

// #3454: on a phone the open search field shared the bar's middle slot with
// the back button, so it got a few pixels and could not be typed into, and
// seven controls competed for the top row. Search and Select now sit in the
// second row, and search opens there as a field the width of the bar, so the
// top row fits a 360px phone with nothing scrolled out of sight.
//
// Laid out in Roboto, as on Android: the test font draws every glyph a full em
// wide, which would make the brand's name wider than it is on a phone.
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

  NotificationsController notifications() {
    final controller = NotificationsController(
      listNotifications: () async => [
        const AppNotification(type: NotificationType.backupDue, link: '/0'),
      ],
      readDisabled: () async => {},
      saveEnabled: (_, _) async => {},
      events: () => const Stream<FileEvent>.empty(),
      session: () => ValueNotifier('token'),
    )..start();
    addTearDown(controller.dispose);
    return controller;
  }

  Future<List<String>> pumpBar(WidgetTester tester, Size size) async {
    final drafts = <String>[];
    final theme = QuarkTheme.dark(themeColor: QuarkThemeColor.classic);
    setViewport(tester, size);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
        ),
        home: QuarkAppBarTrailing(
          actions: [
            ConnectionSheetButton(
              mode: ConnectionMode.local,
              onNavigate: (_) {},
            ),
            NotificationsBell(controller: notifications(), onNavigate: (_) {}),
          ],
          child: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              appBar: testFileTopBar(
                // As the page does: a draft in the field is a search.
                isSearchMode: drafts.isNotEmpty && drafts.last.isNotEmpty,
                onSearchDraft: (draft) => setState(() => drafts.add(draft)),
                onStartSelection: () {},
              ),
              body: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return drafts;
  }

  Finder key(String value) => find.byKey(ValueKey(value));

  const narrow = Size(360, 640);
  const wide = Size(1280, 800);

  for (final size in [narrow, wide]) {
    final label = size == narrow ? 'narrow' : 'wide';

    testWidgets('search opens a field the width of the bar ($label)', (
      tester,
    ) async {
      final drafts = await pumpBar(tester, size);

      await tester.tap(key('file_top_bar_search'));
      await tester.pump();
      await tester.pump();

      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      expect(
        tester.getSize(field).width,
        greaterThanOrEqualTo(size.width * 0.8),
        reason: 'the field is most of the bar wide',
      );
      expect(
        tester.widget<TextField>(field).focusNode!.hasFocus,
        isTrue,
        reason: 'the field is focused when it opens',
      );

      await tester.enterText(field, 'mountain');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(drafts.last, 'mountain');
      expect(tester.widget<TextField>(field).controller!.text, 'mountain');
      expect(
        tester.getSize(field).width,
        greaterThanOrEqualTo(size.width * 0.8),
        reason: 'the field keeps its width once a search is running',
      );
      // Select stays reachable on the search results.
      expect(key('file_top_bar_select'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Close search'));
      await tester.pump();

      expect(field, findsNothing);
      expect(key('file_top_bar_home'), findsOneWidget);
      expect(key('file_top_bar_search'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the top row fits with nothing scrolled away ($label)', (
      tester,
    ) async {
      await pumpBar(tester, size);

      final bar = tester.getRect(find.byType(AppBar));
      final rowBottom = bar.top + kToolbarHeight;
      final brand = tester.getRect(find.byType(QuarkBrandButton));
      final rects = <String, Rect>{};
      for (final value in const [
        'refresh_button',
        'file_top_bar_up',
        'theme_toggle',
        'connection_indicator',
        'notifications_bell',
      ]) {
        final rect = tester.getRect(key(value));
        rects[value] = rect;
        expect(rect.left, greaterThanOrEqualTo(brand.right), reason: value);
        expect(rect.right, lessThanOrEqualTo(bar.right + 0.5), reason: value);
        expect(rect.bottom, lessThanOrEqualTo(rowBottom + 0.5), reason: value);
        expect(
          tester.getSize(key(value)).width,
          greaterThanOrEqualTo(QuarkBarIconButton.size),
          reason: '$value is whole, not scaled down',
        );
      }
      for (final a in rects.entries) {
        for (final b in rects.entries) {
          if (a.key.compareTo(b.key) >= 0) continue;
          final overlap = a.value.intersect(b.value);
          expect(
            overlap.width > 0.5 && overlap.height > 0.5,
            isFalse,
            reason: '${a.key} overlaps ${b.key}',
          );
        }
      }
      // Nothing in the top row hides behind a sideways scroll.
      for (final scrollable
          in find
              .descendant(
                of: find.byType(QuarkToolbarScroller),
                matching: find.byType(Scrollable),
              )
              .evaluate()) {
        final position =
            (scrollable as StatefulElement).state as ScrollableState;
        if (tester.getRect(find.byWidget(scrollable.widget)).top >= rowBottom) {
          continue;
        }
        expect(position.position.maxScrollExtent, 0);
      }

      // Search and Select moved to the second row, where they show at every
      // width.
      for (final value in const [
        'file_top_bar_search',
        'file_top_bar_select',
      ]) {
        final rect = tester.getRect(key(value));
        expect(rect.top, greaterThanOrEqualTo(rowBottom - 0.5), reason: value);
        expect(rect.right, lessThanOrEqualTo(bar.right + 0.5), reason: value);
        expect(
          tester.getSize(key(value)),
          const Size.square(QuarkBarIconButton.tapTargetSize),
          reason: value,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
