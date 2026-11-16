import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// #4150: the sheet a phone's account button opens.
void main() {
  Widget sheet({
    Widget? notifications,
    Widget? connection,
    int runningJobs = 0,
    VoidCallback? onOpenJobs,
    ValueChanged<ThemeMode>? onThemeModeChanged,
    VoidCallback? onSwitchQuark,
  }) => SingleChildScrollView(
    child: QuarkAccountSheet(
      notifications: notifications,
      connection: connection,
      runningJobs: runningJobs,
      onOpenJobs: onOpenJobs ?? () {},
      themeMode: ThemeMode.system,
      onThemeModeChanged: onThemeModeChanged ?? (_) {},
      quarkName: 'Home',
      onSwitchQuark: onSwitchQuark ?? () {},
    ),
  );

  testBothViewports('shows every section it is given, in order', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      sheet(
        notifications: const Text('the notifications'),
        connection: const Text('the connection'),
        runningJobs: 2,
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
    final tops = [
      for (final text in [
        'the notifications',
        '2 running',
        'the connection',
        'System',
        'Home',
      ])
        tester.getTopLeft(find.text(text)).dy,
    ];
    expect(tops, [...tops]..sort());
    expect(find.text('Switch Quark'), findsOneWidget);
  });

  testBothViewports('leaves out the panels it is not given', (
    tester,
    size,
  ) async {
    await pumpAt(tester, sheet(), size: size);
    expect(tester.takeException(), isNull);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Connection'), findsNothing);
    expect(find.text('Nothing running'), findsOneWidget);
  });

  testWidgets('hands back the jobs, theme and switch taps', (tester) async {
    final events = <String>[];
    await pumpAt(
      tester,
      sheet(
        onOpenJobs: () => events.add('jobs'),
        onThemeModeChanged: (mode) => events.add('$mode'),
        onSwitchQuark: () => events.add('switch'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('account_sheet_jobs')));
    await tester.tap(find.byKey(const ValueKey('account_theme_dark')));
    await tester.tap(find.byKey(const ValueKey('account_sheet_switch_quark')));
    expect(events, ['jobs', '${ThemeMode.dark}', 'switch']);
  });
}
