import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/photos/photos_search_bar.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart';

/// #2059: the strip Photos opens to search by name reports what is typed and
/// when it is closed, at phone and desktop widths.
void main() {
  Future<List<String>> pump(WidgetTester tester, Size size) async {
    final events = <String>[];
    setViewport(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(
          body: Column(
            children: [
              PhotosSearchBar(
                onChanged: (query) => events.add('changed($query)'),
                onClose: () => events.add('closed'),
              ),
            ],
          ),
        ),
      ),
    );
    return events;
  }

  for (final (name, size) in [
    ('narrow', narrowViewport),
    ('wide', wideViewport),
  ]) {
    testWidgets('$name: reports the query and the close', (tester) async {
      final events = await pump(tester, size);

      expect(tester.takeException(), isNull);
      // Opening the strip is asking to type, so the field takes the focus.
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('photos_search_field')),
            )
            .autofocus,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const ValueKey('photos_search_field')),
        'beach',
      );
      await tester.tap(find.byKey(const ValueKey('photos_search_close')));

      expect(events, ['changed(beach)', 'closed']);
      expect(find.byTooltip('Close search'), findsOneWidget);
    });

    testWidgets('$name: meets the tap target guidelines', (tester) async {
      await pump(tester, size);

      await expectTapTargetGuidelines(tester);
    });
  }

  // #3363: autofocus does nothing while something else in the scope has the
  // focus, which the Photos page always does.
  testWidgets('the field takes the focus from whatever held it', (
    tester,
  ) async {
    final field = find.byKey(const ValueKey('photos_search_field'));
    final holder = FocusNode();
    addTearDown(holder.dispose);
    final typed = <String>[];
    Future<void> pumpBar({required bool open}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Focus(
            focusNode: holder,
            autofocus: true,
            child: Column(
              children: [
                if (open) PhotosSearchBar(onChanged: typed.add, onClose: () {}),
              ],
            ),
          ),
        ),
      ),
    );

    await pumpBar(open: false);
    await tester.pump();
    expect(holder.hasPrimaryFocus, isTrue);

    await pumpBar(open: true);
    await tester.pump();

    final editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'mp4',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();
    expect(typed, ['mp4']);
  });
}
