import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/file_browser/folder_explainer.dart';

/// #2476: `users`, `groups` and `groups/everyone` say what they are, so a
/// member browsing them learns the home / group / everyone model.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  final explainer = find.byKey(const ValueKey('folder_explainer'));

  Future<void> pumpAt(
    WidgetTester tester,
    String path, {
    String serial = '',
    Size size = wideViewport,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FolderExplainer(serial: serial, path: path),
        ),
      ),
    );
  }

  for (final size in [narrowViewport, wideViewport]) {
    testWidgets('users explains homes at $size', (tester) async {
      await pumpAt(tester, '/users', size: size);

      expect(explainer, findsOneWidget);
      expect(find.text('Home folders'), findsOneWidget);
      expect(find.textContaining('users/<name>'), findsOneWidget);
      expect(find.textContaining('My files'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('groups explains groups, everyone and Share at $size', (
      tester,
    ) async {
      await pumpAt(tester, '/groups', size: size);

      expect(find.text('Group folders'), findsOneWidget);
      expect(find.textContaining('everyone'), findsOneWidget);
      expect(find.textContaining('Share'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('groups/everyone says every account can use it at $size', (
      tester,
    ) async {
      await pumpAt(tester, 'groups/everyone', size: size);

      expect(find.text('Shared with everyone'), findsOneWidget);
      expect(find.textContaining('Every account'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('renders nothing anywhere else', (tester) async {
    for (final path in [
      '',
      '/users/ada',
      '/groups/family',
      '/groups/everyone/Photos',
      '/Documents',
    ]) {
      await pumpAt(tester, path);
      expect(explainer, findsNothing, reason: path);
    }
  });

  testWidgets('renders nothing for a users folder on a USB drive', (
    tester,
  ) async {
    await pumpAt(tester, '/users', serial: 'usb-1234');
    expect(explainer, findsNothing);
  });

  testWidgets('offers no dismiss button', (tester) async {
    await pumpAt(tester, '/groups');
    expect(find.byKey(const ValueKey('welcome_card_dismiss')), findsNothing);
  });
}
