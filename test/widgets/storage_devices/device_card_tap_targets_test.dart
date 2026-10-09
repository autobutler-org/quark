import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/widgets/storage_devices/device_card.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart';

/// #2939: the card's actions are 48dp on a phone and on a desktop, where
/// Material's own defaults would shrink them to 32px. The category chips are
/// labels, not targets, so they stay compact.
void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.linux]) {
    for (final size in [narrowViewport, wideViewport]) {
      final label = size == narrowViewport ? 'narrow' : 'wide';
      testWidgets('actions are 48dp on ${platform.name} ($label)', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        setViewport(tester, size);
        await tester.pumpWidget(
          MaterialApp(
            theme: QuarkTheme.from(QuarkTokens.light, Brightness.light),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: DeviceCard(
                  device: const StorageDevice(
                    name: 'Backup',
                    devicePath: '/dev/sda1',
                    mountPoint: '/mnt/backup',
                    fileSystem: 'ext4',
                    totalBytes: 100,
                    usedBytes: 50,
                    availableBytes: 50,
                    isInternal: false,
                    isEnabled: true,
                    categories: {'media': 10, 'documents': 20},
                  ),
                  isMounting: false,
                  onSetRole: () {},
                  onBackup: () {},
                  onVerify: () {},
                ),
              ),
            ),
          ),
        );

        for (final text in ['Set Role', 'Back Up', 'Verify']) {
          final button = find.ancestor(
            of: find.text(text),
            matching: find.bySubtype<ButtonStyleButton>(),
          );
          expect(tester.getSize(button).height, 48, reason: text);
        }
        await expectTapTargetGuidelines(tester);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
