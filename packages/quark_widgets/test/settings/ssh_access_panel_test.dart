import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The SSH access panel: every state it declares, its callbacks, and its keys.
const _withComment = SshKeyItem(
  fingerprint: 'SHA256:abc/def+ghi',
  type: 'ssh-ed25519',
  comment: 'me@laptop',
);
const _bare = SshKeyItem(fingerprint: 'SHA256:xyz', type: 'ssh-rsa');

void main() {
  testWidgets('shows a spinner while loading', (tester) async {
    await pumpAt(tester, const SshAccessPanel(isLoading: true));
    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byKey(const ValueKey('ssh_enabled_switch')), findsNothing);
  });

  testWidgets('replaces every control with the unavailable reason', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const SshAccessPanel(unavailableReason: 'Run sudo quark install.'),
    );
    expect(find.byKey(const ValueKey('ssh_unavailable')), findsOneWidget);
    expect(find.text('Run sudo quark install.'), findsOneWidget);
    expect(find.byKey(const ValueKey('ssh_enabled_switch')), findsNothing);
    expect(find.byKey(const ValueKey('ssh_add_key')), findsNothing);
    expect(find.byKey(const ValueKey('ssh_set_password')), findsNothing);
  });

  testWidgets('lists keys by comment, or type without one', (tester) async {
    await pumpAt(
      tester,
      const SingleChildScrollView(
        child: SshAccessPanel(enabled: true, keys: [_withComment, _bare]),
      ),
    );
    expect(find.text('me@laptop'), findsOneWidget);
    expect(find.text('ssh-rsa'), findsOneWidget);
    expect(find.byKey(const ValueKey('ssh_key_SHA256:xyz')), findsOneWidget);
    expect(find.textContaining('No keys yet'), findsNothing);
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('ssh_enabled_switch')),
    );
    expect(toggle.value, isTrue);
  });

  testWidgets('says there are no keys', (tester) async {
    await pumpAt(tester, const SingleChildScrollView(child: SshAccessPanel()));
    expect(find.textContaining('No keys yet'), findsOneWidget);
  });

  testWidgets('renders the error the caller handed it', (tester) async {
    await pumpAt(
      tester,
      const SingleChildScrollView(
        child: SshAccessPanel(error: "Couldn't add the key."),
      ),
    );
    expect(find.text("Couldn't add the key."), findsOneWidget);
  });

  testBothViewports('sends every action out', (tester, size) async {
    final events = <String>[];
    await pumpAt(
      tester,
      SingleChildScrollView(
        child: SshAccessPanel(
          keys: const [_withComment],
          onEnabledChanged: (on) => events.add('enabled $on'),
          onAddKey: () => events.add('add'),
          onRemoveKey: (fingerprint) => events.add('remove $fingerprint'),
          onSetPassword: () => events.add('set'),
          onClearPassword: () => events.add('clear'),
        ),
      ),
      size: size,
    );
    for (final key in [
      'ssh_enabled_switch',
      'ssh_add_key',
      'ssh_remove_key_SHA256:abc/def+ghi',
      'ssh_set_password',
      'ssh_clear_password',
    ]) {
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump();
    }
    expect(events, [
      'enabled true',
      'add',
      'remove SHA256:abc/def+ghi',
      'set',
      'clear',
    ]);
  });

  testBothViewports('disables every control while working', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      SingleChildScrollView(
        child: SshAccessPanel(
          keys: const [_withComment],
          isWorking: true,
          onEnabledChanged: (on) => events.add('enabled'),
          onAddKey: () => events.add('add'),
          onRemoveKey: (_) => events.add('remove'),
          onSetPassword: () => events.add('set'),
          onClearPassword: () => events.add('clear'),
        ),
      ),
      size: size,
    );
    for (final key in [
      'ssh_enabled_switch',
      'ssh_add_key',
      'ssh_remove_key_SHA256:abc/def+ghi',
      'ssh_set_password',
      'ssh_clear_password',
    ]) {
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      await tester.tap(finder, warnIfMissed: false);
      await tester.pump();
    }
    expect(events, isEmpty);
  });
}
