import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/settings/settings_updates_tab.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/text_scale.dart';

/// #2605, #2606: the Updates tab, with an update on offer, survives 200% text
/// and every control on it, the release notes link included, is a 48dp
/// target a screen reader can name.
void main() {
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

  // #2954: zero padding drew the focus ring at the icon's and the label's
  // edges. The ring needs an inset, and the resting text still lines up with
  // the version above it.
  for (final MapEntry(key: name, value: size) in largeTextViewports.entries) {
    testWidgets('the focused release notes link has room inside its ring '
        '($name)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
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
SettingsUpdatesTab updatesTab() => SettingsUpdatesTab(
  hasHost: true,
  isAdmin: true,
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
  autoUpdate: true,
  isLoadingAutoUpdate: false,
  autoUpdateError: null,
  onAutoUpdateChanged: (_) {},
);
