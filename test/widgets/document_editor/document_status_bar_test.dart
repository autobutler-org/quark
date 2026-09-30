import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/document_editor/document_status_bar.dart';
import 'package:quark/widgets/document_editor/document_status_item.dart';
import 'package:quark_widgets/quark_widgets.dart';

// The status bar's colors come from the theme's tokens, which hold WCAG AA
// contrast in both themes (#2602). The literal amber and green it used to
// paint "Unsaved" and "Saved" with fell under 3:1 on a light page, and the
// half-alpha labels under 4.5:1.
void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required ThemeData theme,
    bool isReadOnly = false,
    bool dirty = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: DocumentStatusBar(
            darkPage: false,
            onToggleDarkPage: () {},
            wordCount: 12,
            isReadOnly: isReadOnly,
            dirty: dirty,
          ),
        ),
      ),
    );
  }

  Color? iconColor(WidgetTester tester, String label) => tester
      .widget<DocumentStatusItem>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(DocumentStatusItem),
        ),
      )
      .color;

  Color? labelColor(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style?.color;

  for (final (name, theme, tokens) in [
    ('dark', QuarkTheme.dark(), QuarkTokens.dark),
    ('light', QuarkTheme.light(), QuarkTokens.light),
  ]) {
    group('$name theme', () {
      testWidgets('Unsaved is tinted with the warning token', (tester) async {
        await pumpBar(tester, theme: theme, dirty: true);

        expect(iconColor(tester, 'Unsaved'), tokens.warning);
      });

      testWidgets('Saved is tinted with the success token', (tester) async {
        await pumpBar(tester, theme: theme);

        expect(iconColor(tester, 'Saved'), tokens.success);
      });

      testWidgets('labels and neutral icons use the muted token', (
        tester,
      ) async {
        await pumpBar(tester, theme: theme, isReadOnly: true);

        for (final label in ['12 words', 'Private', 'Read-only']) {
          expect(labelColor(tester, label), tokens.mutedForeground);
          expect(iconColor(tester, label), tokens.mutedForeground);
        }
      });
    });
  }
}
