import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The duplicates view's "Keep" choice (#1666): it shows the current choice,
/// offers "Any" and every format given, and reports what was picked.
void main() {
  Future<void> pumpButton(
    WidgetTester tester, {
    Size size = wideViewport,
    String? preferred,
    List<String>? events,
  }) => pumpAt(
    tester,
    Center(
      child: DuplicateFormatButton(
        formats: const ['HEIC', 'JPEG'],
        preferred: preferred,
        onChanged: (f) => events?.add('changed:$f'),
      ),
    ),
    size: size,
  );

  for (final (name, size) in [
    ('narrow', narrowViewport),
    ('wide', wideViewport),
  ]) {
    testWidgets('shows the current choice on a $name viewport', (tester) async {
      await pumpButton(tester, size: size, preferred: 'HEIC');

      expect(find.text('Keep: HEIC'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reads "Any" when nothing is preferred', (tester) async {
    await pumpButton(tester);

    expect(find.text('Keep: Any'), findsOneWidget);
  });

  testWidgets('offers Any and each format, and reports the pick', (
    tester,
  ) async {
    final events = <String>[];
    await pumpButton(tester, preferred: 'HEIC', events: events);

    await tester.tap(find.byKey(const ValueKey('duplicates_keep_format')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('duplicates_keep_format_option_any')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('duplicates_keep_format_option_JPEG')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('duplicates_keep_format')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('duplicates_keep_format_option_any')),
    );
    await tester.pumpAndSettle();

    expect(events, ['changed:JPEG', 'changed:null']);
  });
}
