import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/error_banner.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #4101: one row for every banner. The tone picks the icon, the tint, and
/// whether a screen reader announces it.
void main() {
  final theme = QuarkTheme.from(QuarkTokens.dark, Brightness.dark);
  final scheme = theme.colorScheme;

  Future<void> pump(WidgetTester tester, ErrorBannerTone? tone) {
    return tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: tone == null
              ? const ErrorBanner(message: 'Hello')
              : ErrorBanner(message: 'Hello', tone: tone),
        ),
      ),
    );
  }

  Color background(WidgetTester tester) {
    final box = tester.widget<Container>(
      find.descendant(
        of: find.byType(ErrorBanner),
        matching: find.byType(Container),
      ),
    );
    return (box.decoration! as BoxDecoration).color!;
  }

  bool announced(WidgetTester tester) => tester
      .widget<Semantics>(
        find
            .descendant(
              of: find.byType(ErrorBanner),
              matching: find.byType(Semantics),
            )
            .first,
      )
      .properties
      .liveRegion!;

  testWidgets('defaults to the error tone', (tester) async {
    await pump(tester, null);

    expect(find.byIcon(ErrorBannerTone.error.icon), findsOneWidget);
    expect(background(tester), scheme.errorContainer);
    expect(announced(tester), isTrue);
  });

  final expected = {
    ErrorBannerTone.notice: (scheme.primaryContainer, true),
    ErrorBannerTone.warning: (
      QuarkTokens.dark.warning.withValues(alpha: 0.15),
      false,
    ),
    ErrorBannerTone.info: (scheme.secondaryContainer, false),
  };
  for (final MapEntry(key: tone, value: (tint, live)) in expected.entries) {
    testWidgets('the ${tone.name} tone has its own icon and tint', (
      tester,
    ) async {
      await pump(tester, tone);

      expect(find.byIcon(tone.icon), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
      expect(background(tester), tint);
      expect(announced(tester), live);
    });
  }
}
