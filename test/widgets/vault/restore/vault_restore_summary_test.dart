import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/vault_backup_service.dart';
import 'package:quark/widgets/vault/restore/vault_restore_summary.dart';

import '../../../support/text_scale.dart';

/// #1665: what a restore from a backup drive reports.
void main() {
  Future<void> pump(
    WidgetTester tester,
    VaultRestoreResult result, {
    Size size = wideViewport,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VaultRestoreSummary(result: result)),
      ),
    );
  }

  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';

    testWidgets('reports restored and skipped counts ($label)', (tester) async {
      await pump(
        tester,
        const VaultRestoreResult(
          entriesImported: 3,
          entriesSkipped: 2,
          foldersImported: 1,
          foldersSkipped: 1,
        ),
        size: size,
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('vault_restore_summary')),
        findsOneWidget,
      );
      expect(find.text('Restored 3 entries.'), findsOneWidget);
      expect(
        find.text(
          '2 entries were already in your vault and were left unchanged.',
        ),
        findsOneWidget,
      );
      expect(find.text('Restored 1 folder.'), findsOneWidget);
      expect(find.text('1 folder was already in your vault.'), findsOneWidget);
    });
  }

  testWidgets('a zero count says nothing', (tester) async {
    await pump(tester, const VaultRestoreResult(entriesImported: 1));

    expect(find.text('Restored 1 entry.'), findsOneWidget);
    expect(find.textContaining('already in your vault'), findsNothing);
    expect(find.textContaining('folder'), findsNothing);
  });

  testWidgets('a restore that added nothing says so', (tester) async {
    await pump(tester, const VaultRestoreResult(entriesSkipped: 1));

    expect(find.text('No new entries were restored.'), findsOneWidget);
    expect(
      find.text('1 entry was already in your vault and was left unchanged.'),
      findsOneWidget,
    );
  });
}
