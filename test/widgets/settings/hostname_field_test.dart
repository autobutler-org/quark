import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/error_banner.dart';
import 'package:quark/widgets/settings/hostname_field.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2344: the device name field refuses a bad name itself, sends a good one
/// out trimmed, and says where the Quark is afterwards.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  final field = find.byKey(const ValueKey('hostname_field'));
  final save = find.byKey(const ValueKey('hostname_save'));
  final address = find.byKey(const ValueKey('hostname_address'));
  final renamed = find.byKey(const ValueKey('hostname_renamed'));

  Future<List<String>> pumpField(
    WidgetTester tester,
    Size size, {
    String hostname = 'quark',
    String advertisedHostname = '',
    bool isWorking = false,
    String? error,
    String? renamedTo,
    String? reopenAddress,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final submitted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: HostnameField(
              hostname: hostname,
              advertisedHostname: advertisedHostname,
              isWorking: isWorking,
              error: error,
              renamedTo: renamedTo,
              reopenAddress: reopenAddress,
              onSubmit: submitted.add,
            ),
          ),
        ),
      ),
    );
    return submitted;
  }

  bool enabled(WidgetTester tester) =>
      tester.widget<FilledButton>(save).onPressed != null;

  for (final size in [narrowViewport, wideViewport]) {
    testWidgets('starts with the current name and nothing to do at $size', (
      tester,
    ) async {
      final submitted = await pumpField(tester, size);

      expect(tester.takeException(), isNull);
      expect(tester.widget<TextFormField>(field).controller?.text, 'quark');
      expect(
        tester.widget<Text>(address).data,
        'On your network as quark.local',
      );
      expect(enabled(tester), isFalse);
      expect(renamed, findsNothing);
      expect(find.byType(ErrorBanner), findsNothing);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(submitted, isEmpty);
    });

    testWidgets('a name the Quark would refuse stays in the field at $size', (
      tester,
    ) async {
      final submitted = await pumpField(tester, size);

      await tester.enterText(field, 'My Kitchen');
      await tester.pump();
      expect(enabled(tester), isTrue);
      await tester.tap(save);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text(Errors.invalidHostname), findsOneWidget);
      expect(submitted, isEmpty);

      await tester.enterText(field, '   ');
      await tester.pump();
      await tester.tap(save);
      await tester.pump();
      expect(find.text('Name is required'), findsOneWidget);
      expect(submitted, isEmpty);
    });

    testWidgets('a good name goes out trimmed, by button or enter at $size', (
      tester,
    ) async {
      final submitted = await pumpField(tester, size);

      await tester.enterText(field, ' kitchen ');
      await tester.pump();
      await tester.tap(save);
      await tester.enterText(field, 'attic');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(submitted, ['kitchen', 'attic']);
    });

    testWidgets(
      'a rename in flight shows a loader and takes no more at $size',
      (tester) async {
        final submitted = await pumpField(tester, size, isWorking: true);

        await tester.enterText(field, 'kitchen');
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(QuarkLoader), findsOneWidget);
        expect(enabled(tester), isFalse);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        expect(submitted, isEmpty);
      },
    );

    testWidgets('says the name the device took, and where it is now at $size', (
      tester,
    ) async {
      await pumpField(
        tester,
        size,
        hostname: 'kitchen',
        advertisedHostname: 'kitchen-2',
        renamedTo: 'kitchen-2.local',
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.widget<Text>(address).data,
        'On your network as kitchen-2.local, because another device already '
        'had the name kitchen.',
      );
      expect(
        tester.widget<Text>(renamed).data,
        'This Quark is now at kitchen-2.local.',
      );
    });

    testWidgets('a page on the old name is told what to open at $size', (
      tester,
    ) async {
      await pumpField(
        tester,
        size,
        hostname: 'kitchen',
        renamedTo: 'kitchen.local',
        reopenAddress: 'https://kitchen.local',
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.widget<Text>(renamed).data,
        'This Quark is now at kitchen.local. Open https://kitchen.local to '
        'keep using it.',
      );
    });

    testWidgets('a failed rename shows its sentence at $size', (tester) async {
      await pumpField(tester, size, error: "This Quark can't be renamed.");

      expect(tester.takeException(), isNull);
      expect(
        find.widgetWithText(ErrorBanner, "This Quark can't be renamed."),
        findsOneWidget,
      );
    });
  }

  testWidgets('takes the new name when the Quark is renamed elsewhere', (
    tester,
  ) async {
    await pumpField(tester, wideViewport);
    await pumpField(tester, wideViewport, hostname: 'kitchen');

    expect(tester.widget<TextFormField>(field).controller?.text, 'kitchen');
    expect(enabled(tester), isFalse);
  });
}
