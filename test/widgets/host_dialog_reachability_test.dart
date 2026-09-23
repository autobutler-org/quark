import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/widgets/host_dialog.dart';

/// Regression coverage for #2032: Add Quark saved whatever was typed. An
/// address nothing answers on became the active host, which sent the user
/// into terms and a sign-in form for a Quark that was never there — with no
/// hint that the address was the problem.
///
/// The invariant these tests pin: the dialog hands back an entry only after
/// the address answered, or after the user has been told it did not and
/// asked for it anyway.
void main() {
  late List<String> probed;
  late bool reachable;
  final saved = <HostEntry>[];

  setUp(() {
    probed = [];
    reachable = true;
    saved.clear();
    hostReachabilityProbe = (address) async {
      probed.add(address);
      return reachable;
    };
  });

  tearDown(() => hostReachabilityProbe = AuthService.isReachable);

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final entry = await showDialog<HostEntry>(
                context: context,
                builder: (_) => const HostDialog(isEdit: false),
              );
              if (entry != null) saved.add(entry);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> fillIn(WidgetTester tester, String address) async {
    final fields = find.descendant(
      of: find.byType(HostDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.first, 'Cabin');
    await tester.enterText(fields.last, address);
    await tester.pumpAndSettle();
  }

  // #2310: the image answers mDNS as quark.local; nothing produces
  // quark.home.local, so the hint must not suggest it.
  testWidgets('the address hint names quark.local', (tester) async {
    await openDialog(tester);

    expect(find.text('https://quark.local'), findsOneWidget);
    expect(
      find.text(
        'Usually https://quark.local or the IP address shown on your device.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a reachable address is checked, then saved', (tester) async {
    await openDialog(tester);
    await fillIn(tester, 'http://cabin.local');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(probed, ['http://cabin.local']);
    expect(saved.single.hostAddress, 'http://cabin.local');
  });

  testWidgets('an unreachable address stays in the dialog, unsaved', (
    tester,
  ) async {
    reachable = false;
    await openDialog(tester);
    await fillIn(tester, 'http://localhost:8099');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, isEmpty);
    expect(find.byType(HostDialog), findsOneWidget);
    expect(
      find.byKey(const ValueKey('host_dialog_unreachable')),
      findsOneWidget,
    );
  });

  testWidgets('the second press saves the address that did not answer', (
    tester,
  ) async {
    reachable = false;
    await openDialog(tester);
    await fillIn(tester, 'http://localhost:8099');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save anyway'));
    await tester.pumpAndSettle();

    expect(saved.single.hostAddress, 'http://localhost:8099');
    // Probed once. The second press is the user overruling the answer, not a
    // reason to ask again.
    expect(probed, ['http://localhost:8099']);
  });

  testWidgets('correcting the address asks again instead of saving blind', (
    tester,
  ) async {
    reachable = false;
    await openDialog(tester);
    await fillIn(tester, 'http://localhost:8099');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Save anyway'), findsOneWidget);

    reachable = true;
    await fillIn(tester, 'http://cabin.local');
    expect(find.text('Save anyway'), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(probed, ['http://localhost:8099', 'http://cabin.local']);
    expect(saved.single.hostAddress, 'http://cabin.local');
  });
}
