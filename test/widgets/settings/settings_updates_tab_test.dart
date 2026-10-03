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
        home: Scaffold(
          body: SettingsUpdatesTab(
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
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text("What's in this release"), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectTapTargetGuidelines(tester);
  });
}
