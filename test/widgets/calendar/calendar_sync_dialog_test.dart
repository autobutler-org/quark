import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/calendar_controller.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/calendar/calendar_sync_dialog.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The calendar sync dialog (#1151): the subscription link once it loads,
/// with its copy button, the download and import buttons, and the sentence
/// when the link cannot load.
void main() {
  Future<void> pump(WidgetTester tester, Future<String> Function() url) =>
      tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
          home: Scaffold(
            body: CalendarSyncDialog(
              calendar: CalendarController(
                listEvents: (_, _) async => const [],
                loadSubscriptionUrl: url,
                canListPeople: () => false,
              ),
            ),
          ),
        ),
      );

  testWidgets('shows the link with a copy button once it loads', (
    tester,
  ) async {
    await pump(tester, () async => 'https://quark.local/ical?token=t');
    await tester.pump();
    expect(find.text('https://quark.local/ical?token=t'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar_subscription_copy')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('calendar_import_ics')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar_download_ics')), findsOneWidget);
  });

  testWidgets('a link that fails to load says so', (tester) async {
    const error = ApiException(500, 'load the subscription link');
    await pump(tester, () async => throw error);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('calendar_subscription_copy')),
      findsNothing,
    );
    expect(
      find.text(Errors.message(error, 'load the subscription link')),
      findsOneWidget,
    );
  });
}
