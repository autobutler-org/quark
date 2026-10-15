import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

final DocumentProperties _properties = DocumentProperties(
  title: 'A quarterly report with a title long enough to wrap on a phone',
  author: 'Ada Lovelace',
  subject: 'Revenue and forecasts',
  created: DateTime(2026, 10, 14, 9, 30),
  modified: DateTime(2026, 10, 15, 14, 5),
  pages: 12,
  words: 1234,
  characters: 7020,
  slides: 4,
  sheets: 3,
  application: 'LibreOffice Writer',
  countsSource: 'saved',
);

/// The document properties sheet body's complete, loading, empty, error, and
/// refreshing states at phone and desktop widths.
void main() {
  testBothViewports('shows every property without overflowing', (
    tester,
    size,
  ) async {
    await pumpInSheet(
      tester,
      QuarkDocumentProperties(properties: _properties),
      size: size,
    );

    expect(tester.takeException(), isNull);
    for (final key in [
      'title',
      'author',
      'subject',
      'created',
      'modified',
      'pages',
      'words',
      'characters',
      'slides',
      'sheets',
      'application',
      'counts_source',
    ]) {
      expect(find.byKey(ValueKey('document_property_$key')), findsOneWidget);
    }
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('1,234'), findsNothing);
    expect(find.text('1234'), findsOneWidget);
    expect(
      find.text('Counts as last saved in LibreOffice Writer.'),
      findsOneWidget,
    );
  });

  testBothViewports('shows a loader before properties arrive', (
    tester,
    size,
  ) async {
    await pumpInSheet(
      tester,
      const QuarkDocumentProperties(isLoading: true),
      size: size,
    );
    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.text('No document properties'), findsNothing);
  });

  testBothViewports('shows the caller error and retries', (tester, size) async {
    final events = <String>[];
    await pumpInSheet(
      tester,
      QuarkDocumentProperties(
        error: "Couldn't load properties.",
        onRetry: () => events.add('retry'),
      ),
      size: size,
    );
    expect(find.text("Couldn't load properties."), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('document_properties_retry')));
    expect(events, ['retry']);
  });

  testBothViewports('shows the empty state with no values', (
    tester,
    size,
  ) async {
    await pumpInSheet(
      tester,
      const QuarkDocumentProperties(properties: DocumentProperties()),
      size: size,
    );
    expect(find.text('No document properties'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
  });

  testBothViewports('keeps old properties through a refresh error', (
    tester,
    size,
  ) async {
    await pumpInSheet(
      tester,
      QuarkDocumentProperties(
        properties: _properties,
        isLoading: true,
        error: 'The refresh failed.',
      ),
      size: size,
    );
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('The refresh failed.'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
  });

  testWidgets('explains parsed counts without naming an application', (
    tester,
  ) async {
    await pumpInSheet(
      tester,
      const QuarkDocumentProperties(
        properties: DocumentProperties(words: 42, countsSource: 'parsed'),
      ),
    );
    expect(find.text('Counts from this preview.'), findsOneWidget);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: refresh errors use the error token', (tester) async {
      await pumpInSheet(
        tester,
        QuarkDocumentProperties(properties: _properties, error: 'Offline'),
        brightness: brightness,
      );
      expect(
        tester.widget<Text>(find.text('Offline')).style?.color,
        tokens.error,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testLargeText('survives large text', (tester, size) async {
    await pumpInSheet(
      tester,
      QuarkDocumentProperties(properties: _properties),
      size: size,
    );
    expect(tester.takeException(), isNull);
  });
}
