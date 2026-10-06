import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/connected_devices_service.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/widgets/settings/connected_devices_card.dart';
import 'package:quark/widgets/settings/delete_account_dialog.dart';
import 'package:quark/widgets/settings/help_support_card.dart';
import 'package:quark/widgets/settings/remote_access_card.dart';
import 'package:quark/widgets/settings/reset_quark_dialog.dart';
import 'package:quark/widgets/settings/sbom_expansion_tile.dart';
import 'package:quark/widgets/settings/settings_profile_card.dart';
import 'package:quark/widgets/settings/ssh_key_dialog.dart';
import 'package:quark/widgets/settings/ssh_password_dialog.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/text_scale.dart';

/// #2606, #2603, #2605: the Settings cards and dialogs that only show with a
/// Quark to talk to survive 200% text on a phone and a desktop, and every
/// control in them is labeled and big enough to hit.
void main() {
  final seen = DateTime(2026, 10, 1, 9, 30);

  final widgets = <String, Widget>{
    'remote access, connected': RemoteAccessCard(
      status: const RemoteAccessStatus(
        enabled: true,
        connected: true,
        remoteUrl: 'https://quark.tail1234.ts.net',
      ),
      isLoading: false,
      isWorking: false,
      error: null,
      disconnected: false,
      isAdmin: true,
      onRetry: () {},
      onSetUp: () {},
      onTurnOff: () {},
      onTryAgain: () {},
      onGetHelp: () {},
    ),
    'remote access, connecting': RemoteAccessCard(
      status: const RemoteAccessStatus(enabled: true),
      isLoading: false,
      isWorking: false,
      error: null,
      disconnected: false,
      isAdmin: true,
      onRetry: () {},
      onSetUp: () {},
      onTurnOff: () {},
      onTryAgain: () {},
      onGetHelp: () {},
    ),
    'remote access, failing': RemoteAccessCard(
      status: const RemoteAccessStatus(enabled: true, error: 'tsnet failed'),
      isLoading: false,
      isWorking: false,
      error: null,
      disconnected: false,
      isAdmin: true,
      onRetry: () {},
      onSetUp: () {},
      onTurnOff: () {},
      onTryAgain: () {},
      onGetHelp: () {},
    ),
    'remote access, off': RemoteAccessCard(
      status: const RemoteAccessStatus(enabled: false),
      isLoading: false,
      isWorking: false,
      error: null,
      disconnected: false,
      isAdmin: true,
      onRetry: () {},
      onSetUp: () {},
      onTurnOff: () {},
      onTryAgain: () {},
      onGetHelp: () {},
    ),
    'connected devices': ConnectedDevicesCard(
      devices: [
        ConnectedDevice(
          id: 1,
          ipAddress: '192.168.1.24',
          userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) Safari',
          firstSeenAt: seen,
          lastSeenAt: seen,
          requestCount: 1204,
        ),
      ],
      isLoading: false,
      error: null,
      disconnected: false,
      isAdmin: true,
      onRefresh: () {},
      onRemove: (_) {},
    ),
    'profile': SettingsProfileCard(
      userId: 1,
      username: 'ada',
      avatarVersion: null,
      isBusy: false,
      error: null,
      onPick: () {},
      onRemove: () {},
    ),
    'help and support': const HelpSupportCard(),
    'software list': const SbomExpansionTile(
      title: 'Flutter packages',
      subtitle: '2 packages',
      items: [
        SbomEntry(name: 'go_router', version: '14.0.0', url: 'https://pub.dev'),
        SbomEntry(name: 'http', version: '1.2.0'),
      ],
    ),
    'delete account dialog': DeleteAccountDialog(
      username: 'ada',
      onConfirm: (_) {},
      onCancel: () {},
    ),
    'reset dialog': ResetQuarkDialog(onConfirm: (_, _) {}, onCancel: () {}),
    'SSH key dialog': SshKeyDialog(onSubmit: (_) {}, onCancel: () {}),
    'SSH password dialog': SshPasswordDialog(onSubmit: (_) {}, onCancel: () {}),
  };

  for (final MapEntry(key: name, value: widget) in widgets.entries) {
    testLargeText('the $name lays out', (tester, _) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: widget,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      await expectTapTargetGuidelines(tester);
    });
  }
}
