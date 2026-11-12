import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/restart_controller.dart';
import 'package:quark/models/restart_status.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/settings/restart_quark_section.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// #4019: restarting asks first, shows "Restarting…" until the Quark answers
/// again, and a Quark nothing would start again shows nothing.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  final button = find.byKey(const ValueKey('restart_quark_button'));

  /// Pumps the section. The Quark answers a version request only once
  /// [back] completes, so a test can look at the restarting state first.
  Future<List<String>> pumpSection(
    WidgetTester tester,
    Size size,
    RestartStatus status, {
    Completer<void>? back,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    setViewport(tester, size);

    final calls = <String>[];
    final controller = RestartController(
      getStatus: () async => status,
      restart: () async => calls.add('restart'),
      getInstalledVersion: () async {
        if (back != null && !back.isCompleted) {
          throw const ApiException(502, 'get version');
        }
        return <String, dynamic>{};
      },
      exitPause: const Duration(milliseconds: 10),
      pollInterval: const Duration(milliseconds: 10),
      timeout: timeout,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RestartQuarkSection(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return calls;
  }

  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';

    testWidgets('asks, restarts, and says when Quark is back ($label)', (
      tester,
    ) async {
      final back = Completer<void>();
      final calls = await pumpSection(
        tester,
        size,
        const RestartStatus(available: true),
        back: back,
      );

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Restart Quark?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);

      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restart'));
      // The loader animates, so pump a fixed time rather than settling.
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, ['restart']);
      expect(find.text('Restarting…'), findsOneWidget);
      expect(find.byType(QuarkLoader), findsOneWidget);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      back.complete();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(find.text('Restarting…'), findsNothing);
      expect(find.text('Quark is back.'), findsOneWidget);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    });

    testWidgets('a Quark that never comes back shows an error ($label)', (
      tester,
    ) async {
      await pumpSection(
        tester,
        size,
        const RestartStatus(available: true),
        back: Completer<void>(),
        timeout: const Duration(milliseconds: 30),
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restart'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text(Errors.restartDidNotFinish), findsOneWidget);
      expect(find.text('Restarting…'), findsNothing);
    });

    testWidgets('a Quark nothing would start again shows nothing ($label)', (
      tester,
    ) async {
      await pumpSection(
        tester,
        size,
        const RestartStatus(
          available: false,
          reason: RestartStatus.notSupervised,
        ),
      );
      expect(find.text('Restart Quark'), findsNothing);
      expect(button, findsNothing);
    });
  }
}
