import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/layout/file_viewer_chrome.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #4105: the chrome the audio, video, PDF, SVG and fallback viewers share.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget chrome({VoidCallback? onClose}) => FileViewerChrome(
    name: 'song.mp3',
    onClose: onClose,
    actions: const [Text('page action', key: ValueKey('action'))],
    body: const Text('body'),
  );

  testWidgets('shows the file name, the actions, the toggle and the body', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: chrome()));

    expect(find.text('song.mp3'), findsOneWidget);
    expect(find.byKey(const ValueKey('action')), findsOneWidget);
    expect(find.byType(AppThemeToggle), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('without a closer, Back pops the route it was pushed on', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => chrome())),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(FileViewerChrome), findsNothing);
  });

  testWidgets('a closer replaces Back', (tester) async {
    var closed = 0;
    await tester.pumpWidget(MaterialApp(home: chrome(onClose: () => closed++)));

    await tester.tap(find.byType(BackButton));

    expect(closed, 1);
  });
}
