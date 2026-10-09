import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/hostname_controller.dart';
import 'package:quark/models/hostname_status.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/settings/hostname_field.dart';
import 'package:quark/widgets/settings/hostname_section.dart';

/// #2344: the device name section is there only on a Quark that can be
/// renamed, and a rename made in it moves the app's saved address.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  final section = find.byKey(const ValueKey('hostname_section'));
  final field = find.byKey(const ValueKey('hostname_field'));
  final save = find.byKey(const ValueKey('hostname_save'));
  final renamed = find.byKey(const ValueKey('hostname_renamed'));

  Future<List<String>> pumpSection(
    WidgetTester tester,
    Size size, {
    required Future<HostnameStatus> Function() getStatus,
    Future<HostnameStatus> Function(String name)? setHostname,
    String title = 'Device name',
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final moves = <String>[];
    final controller = HostnameController(
      getStatus: getStatus,
      setHostname:
          setHostname ??
          (name) async => HostnameStatus(available: true, hostname: name),
      events: const Stream<FileEvent>.empty(),
      activeHost: () => 'https://quark.local',
      moveHost: (from, to) async => moves.add('$from -> $to'),
      pageUri: () => Uri.parse('file:///app'),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              HostnameSection(controller: controller, title: title),
              const Text('after'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return moves;
  }

  for (final size in [narrowViewport, wideViewport]) {
    testWidgets("absent on a Quark that can't be renamed at $size", (
      tester,
    ) async {
      await pumpSection(
        tester,
        size,
        getStatus: () async => const HostnameStatus(
          available: false,
          reason: 'unsupported_os',
          hostname: 'quark',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(section, findsNothing);
      expect(find.byType(HostnameField), findsNothing);
      expect(find.text('Device name'), findsNothing);
      // Nothing is left behind where it would have been.
      expect(tester.getTopLeft(find.text('after')).dy, 16);
    });

    testWidgets("absent when the Quark can't be asked at $size", (
      tester,
    ) async {
      await pumpSection(
        tester,
        size,
        getStatus: () async => throw const ApiException(404, 'load'),
      );

      expect(tester.takeException(), isNull);
      expect(section, findsNothing);
      expect(find.byType(HostnameField), findsNothing);
    });

    testWidgets('renames the Quark and moves the saved address at $size', (
      tester,
    ) async {
      final moves = await pumpSection(
        tester,
        size,
        title: 'Name this Quark',
        getStatus: () async =>
            const HostnameStatus(available: true, hostname: 'quark'),
      );

      expect(tester.takeException(), isNull);
      expect(section, findsOneWidget);
      expect(find.text('Name this Quark'), findsOneWidget);
      expect(tester.widget<TextFormField>(field).controller?.text, 'quark');

      await tester.enterText(field, 'kitchen');
      await tester.pump();
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(moves, ['https://quark.local -> https://kitchen.local']);
      expect(
        tester.widget<Text>(renamed).data,
        'This Quark is now at kitchen.local.',
      );
      expect(tester.widget<TextFormField>(field).controller?.text, 'kitchen');
    });

    testWidgets('a refused rename says why and moves nothing at $size', (
      tester,
    ) async {
      final moves = await pumpSection(
        tester,
        size,
        getStatus: () async =>
            const HostnameStatus(available: true, hostname: 'quark'),
        setHostname: (name) async =>
            throw const MessageException("this Quark can't be renamed"),
      );

      await tester.enterText(field, 'kitchen');
      await tester.pump();
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text("This Quark can't be renamed."), findsOneWidget);
      expect(renamed, findsNothing);
      expect(moves, isEmpty);
    });
  }
}
