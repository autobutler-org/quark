import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/utils/emulator_loopback.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/host_dialog.dart';
import 'package:quark/widgets/quark_connect_form.dart';

/// #2070: on an Android emulator `localhost` is the emulator, and neither Add
/// Quark form said to type `10.0.2.2` instead. Both now say so under the
/// address field as soon as a loopback address is typed.
///
/// `flutter test` reports Android as the platform unless a test says
/// otherwise, so only the iOS cases carry a variant.
void main() {
  const narrow = Size(360, 640);
  const wide = Size(1280, 800);
  final hint = find.byKey(const ValueKey('emulator_loopback_hint'));

  setUp(() => hostReachabilityProbe = (_) async => false);
  tearDown(() => hostReachabilityProbe = AuthService.isReachable);

  void setViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpConnectForm(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: QuarkConnectForm(onConnected: () {}, autofocus: false),
        ),
      ),
    ),
  );

  Future<void> openHostDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<HostEntry>(
              context: context,
              builder: (_) => const HostDialog(isEdit: false),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  // EditableText rather than TextField: the dialog's fields are Cupertino ones
  // on iOS.
  Finder dialogFields() => find.descendant(
    of: find.byType(HostDialog),
    matching: find.byType(EditableText),
  );
  Finder dialogAddressField() => dialogFields().last;

  for (final (name, size) in const [('narrow', narrow), ('wide', wide)]) {
    group('$name viewport', () {
      testWidgets('connect form explains 10.0.2.2 once localhost is typed', (
        tester,
      ) async {
        setViewport(tester, size);
        await pumpConnectForm(tester);
        expect(hint, findsNothing);

        await tester.enterText(find.byType(TextField), 'localhost:8080');
        await tester.pump();

        expect(hint, findsOneWidget);
        expect(tester.widget<Text>(hint).data, contains(emulatorHostAlias));
        expect(tester.takeException(), isNull);
      });

      testWidgets('host dialog explains 10.0.2.2 once localhost is typed', (
        tester,
      ) async {
        setViewport(tester, size);
        await openHostDialog(tester);
        expect(hint, findsNothing);

        await tester.enterText(dialogAddressField(), 'http://127.0.0.1:8080');
        await tester.pump();

        expect(hint, findsOneWidget);
        expect(tester.widget<Text>(hint).data, contains(emulatorHostAlias));
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('an ordinary address shows no hint', (tester) async {
    await pumpConnectForm(tester);

    await tester.enterText(find.byType(TextField), 'quark.local');
    await tester.pump();

    expect(hint, findsNothing);
  });

  testWidgets('the hint goes away when the address is corrected', (
    tester,
  ) async {
    await pumpConnectForm(tester);
    await tester.enterText(find.byType(TextField), 'localhost:8080');
    await tester.pump();
    expect(hint, findsOneWidget);

    await tester.enterText(find.byType(TextField), '10.0.2.2:8080');
    await tester.pump();

    expect(hint, findsNothing);
  });

  testWidgets('connect form keeps the hint beside a failed connection', (
    tester,
  ) async {
    await pumpConnectForm(tester);
    await tester.enterText(find.byType(TextField), 'localhost:8080');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text(Errors.couldNotConnect), findsOneWidget);
    expect(hint, findsOneWidget);
  });

  testWidgets('host dialog keeps the hint beside "Save anyway"', (
    tester,
  ) async {
    await openHostDialog(tester);
    await tester.enterText(dialogFields().first, 'Dev');
    await tester.enterText(dialogAddressField(), 'localhost:8080');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Save anyway'), findsOneWidget);
    expect(hint, findsOneWidget);
  });

  testWidgets(
    'iOS shows no hint: its simulator shares the machine\'s localhost',
    (tester) async {
      await pumpConnectForm(tester);
      await tester.enterText(find.byType(TextField), 'localhost:8080');
      await tester.pump();
      expect(hint, findsNothing);

      await openHostDialog(tester);
      await tester.enterText(dialogAddressField(), 'localhost:8080');
      await tester.pump();
      expect(hint, findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
