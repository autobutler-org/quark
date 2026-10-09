import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/document_editor/document_status_bar.dart';
import 'package:quark/widgets/document_editor/document_status_item.dart';
import 'package:quark_widgets/quark_widgets.dart';

// #2602: the status bar's colors come from the theme's tokens. It used to
// paint "Unsaved" and "Saved" with literal amber and green, which a theme
// cannot move to a contrast-safe shade, and its labels with onSurface at
// half alpha, under 4.5:1. Each theme here moves the tokens off their
// defaults, so a literal color cannot pass by matching one.
void main() {
  const warning = Color(0xFF9A3412);
  const success = Color(0xFF166534);
  const muted = Color(0xFF52525B);

  Future<void> pumpBar(
    WidgetTester tester, {
    required QuarkTokens tokens,
    required Brightness brightness,
    bool isReadOnly = false,
    bool dirty = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(tokens, brightness),
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

  for (final (name, base, brightness) in [
    ('dark', QuarkTokens.dark, Brightness.dark),
    ('light', QuarkTokens.light, Brightness.light),
  ]) {
    final tokens = base.copyWith(
      warning: warning,
      success: success,
      mutedForeground: muted,
    );

    group('$name theme', () {
      testWidgets('Unsaved is tinted with the warning token', (tester) async {
        await pumpBar(
          tester,
          tokens: tokens,
          brightness: brightness,
          dirty: true,
        );

        expect(iconColor(tester, 'Unsaved'), warning);
      });

      testWidgets('Saved is tinted with the success token', (tester) async {
        await pumpBar(tester, tokens: tokens, brightness: brightness);

        expect(iconColor(tester, 'Saved'), success);
      });

      testWidgets('labels and neutral icons use the muted token', (
        tester,
      ) async {
        await pumpBar(
          tester,
          tokens: tokens,
          brightness: brightness,
          isReadOnly: true,
        );

        for (final label in ['12 words', 'Private', 'Read-only']) {
          expect(labelColor(tester, label), muted);
          expect(iconColor(tester, label), muted);
        }
      });
    });
  }
}
