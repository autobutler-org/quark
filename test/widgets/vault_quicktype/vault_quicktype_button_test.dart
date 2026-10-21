import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/quicktype_controller.dart';
import 'package:quark/controllers/vault_biometric_controller.dart';
import 'package:quark/controllers/vault_controller.dart';
import 'package:quark/services/quicktype_identities.dart';
import 'package:quark/services/vault_biometric.dart';
import 'package:quark/widgets/vault_quicktype/vault_quicktype_button.dart';

/// #3599: the vault bar's QuickType button and the opt-in it opens.
void main() {
  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    group('at ${size.width.toInt()}x${size.height.toInt()}', () {
      late bool storedOptIn;
      late List<String> calls;

      setUp(() {
        storedOptIn = false;
        calls = [];
      });

      /// A QuickType controller over a fake store, following a biometric
      /// unlock that is on when [biometricOn] says so.
      Future<QuickTypeController> controller(
        WidgetTester tester, {
        bool biometricOn = true,
        bool supported = true,
      }) async {
        final vault = VaultController(
          fetchKey: () async => null,
          session: ValueNotifier('token'),
        );
        final biometric = VaultBiometricController(
          support: () async => (
            availability: VaultBiometricAvailability.available,
            kind: VaultBiometricKind.faceId,
          ),
          storedFingerprint: (_) async => biometricOn ? Uint8List(16) : null,
          account: () async => 'acct_0123456789abcdef0123456789abcdef',
        );
        final quickType = QuickTypeController(
          supported: supported,
          readOptIn: () async => storedOptIn,
          writeOptIn: (on) async => storedOptIn = on,
          replace: (List<QuickTypeIdentity> _) async {
            calls.add('replace');
            return true;
          },
          clear: () async => calls.add('clear'),
          account: () async => 'acct_0123456789abcdef0123456789abcdef',
        );
        addTearDown(() {
          quickType.dispose();
          biometric.dispose();
          vault.dispose();
        });
        await biometric.refresh();
        quickType.start(vault: vault, biometric: biometric);
        await tester.pump();
        return quickType;
      }

      Future<void> pump(
        WidgetTester tester,
        QuickTypeController quickType,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: [VaultQuickTypeButton(controller: quickType)],
              ),
            ),
          ),
        );
        await tester.pump();
      }

      final button = find.byKey(const ValueKey('vault_quicktype_button'));
      final settings = find.byKey(const ValueKey('vault_quicktype_settings'));

      testWidgets('shows nothing without biometric unlock', (tester) async {
        await pump(tester, await controller(tester, biometricOn: false));
        expect(button, findsNothing);
      });

      testWidgets('shows nothing off iOS', (tester) async {
        await pump(tester, await controller(tester, supported: false));
        expect(button, findsNothing);
      });

      testWidgets('opens the setting, off, saying what iOS stores '
          'unencrypted', (tester) async {
        await pump(tester, await controller(tester));
        await tester.tap(button);
        await tester.pumpAndSettle();

        expect(settings, findsOneWidget);
        expect(
          find.textContaining(
            'site address and username of each login '
            'unencrypted',
          ),
          findsOneWidget,
        );
        final toggle = tester.widget<SwitchListTile>(
          find.descendant(of: settings, matching: find.byType(SwitchListTile)),
        );
        expect(toggle.value, isFalse);
      });

      testWidgets('the switch turns it on and off', (tester) async {
        final quickType = await controller(tester);
        await pump(tester, quickType);
        await tester.tap(button);
        await tester.pumpAndSettle();
        final toggle = find.descendant(
          of: settings,
          matching: find.byType(SwitchListTile),
        );

        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(quickType.enabled, isTrue);
        expect(storedOptIn, isTrue);
        expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(quickType.enabled, isFalse);
        expect(storedOptIn, isFalse);
        expect(calls.last, 'clear');
      });
    });
  }
}
