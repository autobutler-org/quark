import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/settings/settings_updates_tab.dart';

import '../../support/tap_targets.dart';

/// "What's in this release" used to be a text button shrunk to its label
/// (#2605).
void main() {
  for (final (label, size) in [
    ('narrow', narrowViewport),
    ('wide', wideViewport),
  ]) {
    testWidgets('the release notes link is a 48 pixel target ($label)', (
      tester,
    ) async {
      setViewport(tester, size);
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsUpdatesTab(
              hasHost: true,
              isAdmin: false,
              disconnected: false,
              installedVersion: 'v1.2.3',
              installedReleaseUrl: 'https://example.com/v1.2.3',
              availableVersions: const [],
              selectedVersion: null,
              isLoadingVersion: false,
              isUpdating: false,
              versionError: null,
              onSelectVersion: (_) {},
              onUpdate: () {},
              onOpenReleaseNotes: opened.add,
              autoUpdate: false,
              isLoadingAutoUpdate: false,
              autoUpdateError: null,
              onAutoUpdateChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.text("What's in this release"));
      await tester.pump();

      expect(opened, ['https://example.com/v1.2.3']);
      await expectTapTargetsMeetGuideline(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
