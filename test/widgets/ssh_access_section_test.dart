import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/ssh_access_controller.dart';
import 'package:quark/models/ssh_access_status.dart';
import 'package:quark/widgets/settings/ssh_access_section.dart';

/// #2131: turning SSH on opens a shell to the network, so it asks first; and
/// the password dialog will not submit a short or mistyped password.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  final toggle = find.byKey(const ValueKey('ssh_enabled_switch'));

  Future<List<String>> pumpSection(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final calls = <String>[];
    final controller = SshAccessController(
      getStatus: () async =>
          const SshAccessStatus(available: true, enabled: false, keys: []),
      setEnabled: (on) async => calls.add('enabled $on'),
      setPassword: (password) async => calls.add('password $password'),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SshAccessSection(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return calls;
  }

  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';

    testWidgets('asks before turning SSH on ($label)', (tester) async {
      final calls = await pumpSection(tester, size);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('Turn on SSH access?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(calls, ['enabled true']);
    });

    testWidgets('sets a password only once it is typed twice ($label)', (
      tester,
    ) async {
      final calls = await pumpSection(tester, size);
      final setPassword = find.byKey(const ValueKey('ssh_set_password'));
      await tester.ensureVisible(setPassword);
      await tester.tap(setPassword);
      await tester.pumpAndSettle();

      final submit = find.byKey(const ValueKey('ssh_password_submit'));
      await tester.enterText(
        find.byKey(const ValueKey('ssh_password_field')),
        'short',
      );
      await tester.enterText(
        find.byKey(const ValueKey('ssh_password_confirm_field')),
        'short',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('ssh_password_field')),
        'long enough password',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('ssh_password_confirm_field')),
        'long enough password',
      );
      await tester.pump();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(calls, ['password long enough password']);
      expect(find.text('SSH password set'), findsOneWidget);
    });
  }
}
