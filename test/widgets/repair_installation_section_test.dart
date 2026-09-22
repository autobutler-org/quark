import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/repair_controller.dart';
import 'package:quark/models/repair_status.dart';
import 'package:quark/widgets/settings/repair_installation_section.dart';

/// #2121: repair restarts the Quark, so it asks first; an outdated unit gets
/// the one-time install command; a Quark that can't repair shows nothing.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  final button = find.byKey(const ValueKey('repair_installation_button'));

  Future<List<String>> pumpSection(
    WidgetTester tester,
    Size size,
    RepairStatus status,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final calls = <String>[];
    final controller = RepairController(
      getStatus: () async => status,
      repair: () async => calls.add('repair'),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RepairInstallationSection(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return calls;
  }

  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';

    testWidgets('asks before repairing ($label)', (tester) async {
      final calls = await pumpSection(
        tester,
        size,
        const RepairStatus(available: true),
      );

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Repair installation?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);

      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Repair'));
      await tester.pumpAndSettle();
      expect(calls, ['repair']);
      expect(find.textContaining('Quark is restarting'), findsOneWidget);
    });

    testWidgets('an outdated unit shows the install command ($label)', (
      tester,
    ) async {
      await pumpSection(
        tester,
        size,
        const RepairStatus(available: false, reason: RepairStatus.unitOutdated),
      );
      expect(button, findsNothing);
      expect(find.text('sudo quark install'), findsOneWidget);
    });

    testWidgets('a Quark that is not the service shows nothing ($label)', (
      tester,
    ) async {
      await pumpSection(
        tester,
        size,
        const RepairStatus(available: false, reason: RepairStatus.notService),
      );
      expect(find.text('Repair installation'), findsNothing);
      expect(button, findsNothing);
    });
  }
}
