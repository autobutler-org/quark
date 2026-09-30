/// Tests for [QuarkSheet] and [showQuarkSheet], the one bottom sheet every
/// sheet in the app goes through.
///
/// Guards #2585: a sheet whose content was taller than a phone filled the
/// whole screen, left no scrim to tap, had no close button, and gave every
/// drag to its scroll view, so on a phone it could not be closed at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// A page with one button that opens a sheet around [body], recording what
/// the sheet completed with in [results].
Widget _opener(Widget body, List<String?> results) => Builder(
  builder: (context) => Center(
    child: TextButton(
      key: const ValueKey('open'),
      onPressed: () async {
        results.add(
          await showQuarkSheet<String>(
            context,
            title: 'Members',
            builder: (_) => body,
          ),
        );
      },
      child: const Text('Open'),
    ),
  ),
);

/// Content far taller than any viewport.
final Widget _tallBody = Column(
  children: [
    for (var i = 0; i < 60; i++)
      SizedBox(height: 48, child: Text('Member $i with a long name ' * 3)),
  ],
);

Future<void> _open(
  WidgetTester tester,
  Size size,
  List<String?> results, {
  Widget? body,
  Brightness brightness = Brightness.dark,
}) async {
  await pumpAt(
    tester,
    _opener(body ?? _tallBody, results),
    size: size,
    brightness: brightness,
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
  expect(find.byType(QuarkSheet), findsOneWidget);
}

void main() {
  testBothViewports('shows the title, handle and close button', (
    tester,
    size,
  ) async {
    await _open(tester, size, []);
    expect(find.text('Members'), findsOneWidget);
    expect(find.byKey(const ValueKey('quark_sheet_handle')), findsOneWidget);
    expect(find.byKey(const ValueKey('quark_sheet_close')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('the close button closes the sheet', (tester, size) async {
    final results = <String?>[];
    await _open(tester, size, results);
    await tester.tap(find.byKey(const ValueKey('quark_sheet_close')));
    await tester.pumpAndSettle();
    expect(find.byType(QuarkSheet), findsNothing);
    expect(results, [null]);
  });

  testBothViewports('tall content stays under the cap and scrolls inside it', (
    tester,
    size,
  ) async {
    await _open(tester, size, []);
    final sheet = tester.getRect(find.byType(QuarkSheet));
    expect(sheet.height, lessThanOrEqualTo(size.height * 0.85));
    expect(sheet.top, greaterThan(0));

    // The content scrolls; the header does not move.
    final titleTop = tester.getTopLeft(find.text('Members')).dy;
    await tester.drag(
      find.text('Member 5 with a long name ' * 3),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.byType(QuarkSheet), findsOneWidget);
    expect(tester.getTopLeft(find.text('Members')).dy, titleTop);
  });

  testBothViewports('a tap on the scrim above the sheet closes it', (
    tester,
    size,
  ) async {
    final results = <String?>[];
    await _open(tester, size, results);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(QuarkSheet), findsNothing);
    expect(results, [null]);
  });

  for (final (part, finder) in [
    ('handle', find.byKey(const ValueKey('quark_sheet_handle'))),
    ('header', find.text('Members')),
  ]) {
    testBothViewports('a swipe down on the $part closes it', (
      tester,
      size,
    ) async {
      await _open(tester, size, []);
      await tester.drag(finder, Offset(0, size.height));
      await tester.pumpAndSettle();
      expect(find.byType(QuarkSheet), findsNothing);
    });
  }

  testBothViewports('system back closes it', (tester, size) async {
    await _open(tester, size, []);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(QuarkSheet), findsNothing);
  });

  testBothViewports('moves clear of the keyboard', (tester, size) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await _open(tester, size, [], body: const TextField());
    final field = tester.getRect(find.byType(TextField));
    expect(field.bottom, lessThanOrEqualTo(size.height - 300));
    expect(tester.takeException(), isNull);
  });

  testBothViewports('fires onClose once when drawn directly', (
    tester,
    size,
  ) async {
    final closes = <String>[];
    await pumpAt(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: QuarkSheet(
          title: 'Members',
          onClose: () => closes.add('close'),
          child: _tallBody,
        ),
      ),
      size: size,
    );
    expect(
      tester.getSize(find.byType(QuarkSheet)).height,
      lessThanOrEqualTo(size.height * QuarkSheet.maxHeightFactor),
    );
    await tester.tap(find.byKey(const ValueKey('quark_sheet_close')));
    await tester.pump();
    expect(closes, ['close']);
    expect(tester.takeException(), isNull);
  });

  testBothViewports(
    'hands a list that scrolls itself the space under the cap',
    (tester, size) async {
      await pumpAt(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: QuarkSheet(
            title: 'Members',
            onClose: () {},
            scrollable: false,
            child: ListView(
              children: [
                for (var i = 0; i < 60; i++) ListTile(title: Text('Member $i')),
              ],
            ),
          ),
        ),
        size: size,
      );
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(
        tester.getSize(find.byType(QuarkSheet)).height,
        lessThanOrEqualTo(size.height * QuarkSheet.maxHeightFactor),
      );
      await tester.drag(find.text('Member 3'), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('Member 3'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the close button carries a tooltip', (tester) async {
    await _open(tester, narrowViewport, []);
    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('quark_sheet_close')),
    );
    expect(button.tooltip, 'Close');
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the sheet is painted with the card token', (
      tester,
    ) async {
      await _open(tester, narrowViewport, [], brightness: brightness);
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.backgroundColor, tokens.card);
      final handle = tester.widget<Container>(
        find.byKey(const ValueKey('quark_sheet_handle')),
      );
      expect(
        (handle.decoration! as BoxDecoration).color,
        tokens.mutedForeground,
      );
    });
  }
}
