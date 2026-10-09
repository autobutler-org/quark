import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/widgets/settings/connected_devices_card.dart';
import 'package:quark/widgets/settings/remote_access_card.dart';
import 'package:quark/widgets/settings/settings_about_tab.dart';
import 'package:quark/widgets/settings/settings_updates_tab.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2607: every busy indicator in Settings is a `QuarkLoader`, which pulses
/// under reduced motion, never a Material spinner, which turns regardless.
void main() {
  SettingsUpdatesTab updatesTab({
    bool isLoadingVersion = false,
    bool isUpdating = false,
    bool isLoadingAutoUpdate = false,
  }) => SettingsUpdatesTab(
    hasHost: true,
    isAdmin: true,
    disconnected: false,
    installedVersion: 'v1.42.0',
    installedReleaseUrl: null,
    availableVersions: const ['v1.43.0', 'v1.42.0'],
    selectedVersion: 'v1.43.0',
    isLoadingVersion: isLoadingVersion,
    isUpdating: isUpdating,
    versionError: null,
    onSelectVersion: (_) {},
    onUpdate: () {},
    onOpenReleaseNotes: (_) {},
    autoUpdate: true,
    isLoadingAutoUpdate: isLoadingAutoUpdate,
    autoUpdateError: null,
    onAutoUpdateChanged: (_) {},
  );

  RemoteAccessCard remoteAccess({
    RemoteAccessStatus? status,
    bool isLoading = false,
    bool isWorking = false,
  }) => RemoteAccessCard(
    status: status,
    isLoading: isLoading,
    isWorking: isWorking,
    error: null,
    disconnected: false,
    isAdmin: true,
    onRetry: () {},
    onSetUp: () {},
    onTurnOff: () {},
    onTryAgain: () {},
  );

  final busy = <String, Widget>{
    'updates, reading the version': updatesTab(isLoadingVersion: true),
    'updates, updating': updatesTab(isUpdating: true),
    'updates, reading automatic updates': updatesTab(isLoadingAutoUpdate: true),
    'remote access, reading': remoteAccess(isLoading: true),
    'remote access, enabling': remoteAccess(
      status: const RemoteAccessStatus(enabled: false),
      isWorking: true,
    ),
    'remote access, connecting': remoteAccess(
      status: const RemoteAccessStatus(enabled: true),
    ),
    'remote access, trying again': remoteAccess(
      status: const RemoteAccessStatus(enabled: true, error: 'down'),
      isWorking: true,
    ),
    'about, reading the software list': SettingsAboutTab(
      appVersion: 'v1.42.0',
      appReleaseUrl: null,
      onOpenReleaseNotes: (_) {},
      onOpenTerms: () {},
      isLoadingSbom: true,
      sbomError: null,
      flutterSbom: null,
      goSbom: null,
    ),
    'connected devices, reading': ConnectedDevicesCard(
      devices: const [],
      isLoading: true,
      error: null,
      disconnected: false,
      isAdmin: true,
      onRefresh: () {},
      onRemove: (_) {},
    ),
  };

  for (final MapEntry(key: name, value: widget) in busy.entries) {
    testWidgets('$name shows a pulsing loader under reduced motion', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
          home: Scaffold(body: widget),
        ),
      );
      await tester.pump();
      // The devices list sits behind an expansion tile. No pumpAndSettle:
      // a loader never settles.
      final collapsed = find.text('Client connections');
      if (collapsed.evaluate().isNotEmpty) {
        await tester.tap(collapsed);
        await tester.pump(const Duration(seconds: 1));
      }

      // At least one: a busy refresh button is a loader too.
      expect(find.byType(QuarkLoader), findsWidgets);
      expect(
        find.byWidgetPredicate((w) => w is ProgressIndicator),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
