import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/settings/reset_quark_dialog.dart';
import 'package:quark/widgets/settings/settings_updates_tab.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' show setViewport;
import '../../support/text_scale.dart';

/// #2792: the Updates tab says updates are manual and has no automatic
/// updates switch. #2605, #2606: the tab, with an update on offer, survives
/// 200% text, and at both text sizes every control on it, the release notes
/// link included, is a 48dp target a screen reader can name.
///
/// #4151: Reset this Quark lives at the end of the tab's Maintenance group,
/// for admins only, rather than beside Delete account.
void main() {
  const maintenance = ValueKey('settings_maintenance');
  const reset = ValueKey('settings_reset_quark');

  Future<void> pumpTab(WidgetTester tester, {bool isAdmin = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(body: updatesTab(isAdmin: isAdmin)),
      ),
    );
    await tester.pump();
  }

  for (final (name, size) in [
    ('narrow', narrowViewport),
    ('wide', wideViewport),
  ]) {
    testWidgets('an admin finds the reset last, in Maintenance ($name)', (
      tester,
    ) async {
      setViewport(tester, size);
      await pumpTab(tester);

      expect(find.text('Maintenance'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(maintenance),
          matching: find.byKey(reset),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byKey(reset),
          matching: find.byKey(const ValueKey('reset_quark_box')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a member gets no reset and no Maintenance group', (
    tester,
  ) async {
    await pumpTab(tester, isAdmin: false);

    expect(find.byKey(maintenance), findsNothing);
    expect(find.byKey(reset), findsNothing);
    expect(find.text('Reset this Quark'), findsNothing);
  });

  // #2479: the entry names the box in the dialog that decides about attached
  // drives, and the dialog asks for the password before anything is sent.
  testWidgets('the reset names its drives control and asks for a password', (
    tester,
  ) async {
    setViewport(tester, wideViewport);
    await pumpTab(tester);

    expect(
      find.descendant(
        of: find.byKey(reset),
        matching: find.textContaining('“$kResetQuarkDevicesLabel”'),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(reset));
    await tester.tap(find.byKey(reset));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('reset_quark_devices')),
        matching: find.text(kResetQuarkDevicesLabel),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('reset_quark_password_field')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('reset_quark_submit')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('says updates are manual and offers no automatic switch', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(body: updatesTab()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('updates_manual_note')), findsOneWidget);
    expect(find.textContaining('Updates are manual'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.textContaining('Automatic updates'), findsNothing);
    expect(find.text('Start update'), findsOneWidget);
  });

  testLargeText('the tab with an update on offer lays out', (tester, _) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(body: updatesTab()),
      ),
    );
    await tester.pump();

    expect(find.text("What's in this release"), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectTapTargetGuidelines(tester);
  });

  // #2605: the release notes link was a Size.zero, shrink-wrapped target.
  for (final (name, size) in [
    ('narrow', narrowViewport),
    ('wide', wideViewport),
  ]) {
    testWidgets('every control is a 48dp target ($name)', (tester) async {
      setViewport(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
          home: Scaffold(body: updatesTab()),
        ),
      );

      final link = find.ancestor(
        of: find.text("What's in this release"),
        matching: find.byWidgetPredicate((w) => w is TextButton),
      );
      expect(
        tester.getSize(link).height,
        greaterThanOrEqualTo(kMinInteractiveDimension),
      );
      await expectTapTargetGuidelines(tester);
    });
  }

  // #2954: zero padding drew the focus ring at the icon's and the label's
  // edges. The ring needs an inset, and the resting text still lines up with
  // the version above it.
  for (final MapEntry(key: name, value: size) in largeTextViewports.entries) {
    testWidgets('the focused release notes link has room inside its ring '
        '($name)', (tester) async {
      setViewport(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
          home: Scaffold(body: updatesTab()),
        ),
      );
      final link = find.ancestor(
        of: find.text("What's in this release"),
        matching: find.byWidgetPredicate((w) => w is TextButton),
      );
      Focus.of(
        tester.element(find.text("What's in this release")),
      ).requestFocus();
      await tester.pump();

      final button = tester.getRect(link);
      final icon = tester.getRect(
        find.descendant(of: link, matching: find.byType(Icon)),
      );
      final label = tester.getRect(find.text("What's in this release"));
      final version = tester.getRect(find.text('v1.42.0'));
      final inset = QuarkTokens.dark.spacingSm;

      expect(icon.left - button.left, greaterThanOrEqualTo(inset));
      expect(button.right - label.right, greaterThanOrEqualTo(inset));
      expect(icon.left, moreOrLessEquals(version.left));
      expect(tester.takeException(), isNull);
    });
  }
}

/// The tab with an update on offer and release notes for the installed
/// version.
SettingsUpdatesTab updatesTab({bool isAdmin = true}) => SettingsUpdatesTab(
  hasHost: true,
  isAdmin: isAdmin,
  disconnected: false,
  installedVersion: 'v1.42.0',
  installedReleaseUrl: 'https://example.com/releases/v1.42.0',
  availableVersions: const ['v1.43.0', 'v1.42.0'],
  selectedVersion: 'v1.43.0',
  isLoadingVersion: false,
  isUpdating: false,
  versionError: null,
  onSelectVersion: (_) {},
  onUpdate: () {},
  onOpenReleaseNotes: (_) {},
);
