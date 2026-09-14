import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/photos/album_name_dialog.dart';

/// #1916: album names are unique among siblings, ignoring case, and cannot
/// contain `/`. The dialog refuses both before the Quark has to.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  final field = find.byKey(const ValueKey('album_name_field'));
  final save = find.byKey(const ValueKey('album_name_save'));

  bool canSave(WidgetTester tester) =>
      tester.widget<FilledButton>(save).onPressed != null;

  /// Opens the dialog at [size]; the returned list gets what it pops with.
  Future<List<String?>> open(
    WidgetTester tester, {
    Size size = wideViewport,
    String initial = '',
    bool Function(String name)? isNameTaken,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final results = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(
              await AlbumNameDialog.show(
                context,
                title: 'Rename album',
                initial: initial,
                isNameTaken: isNameTaken,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';

    testWidgets('a slash blocks saving and says why ($label)', (tester) async {
      final results = await open(tester, size: size);

      await tester.enterText(field, 'Trips/Japan');
      await tester.pump();

      expect(find.text(Errors.albumNameHasSlash), findsOneWidget);
      expect(canSave(tester), isFalse);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(results, isEmpty);
    });

    testWidgets('a sibling clash blocks saving and says why ($label)', (
      tester,
    ) async {
      await open(tester, size: size, isNameTaken: (name) => name == 'Japan');

      await tester.enterText(field, ' Japan ');
      await tester.pump();

      expect(find.text(Errors.albumNameTaken), findsOneWidget);
      expect(canSave(tester), isFalse);
    });
  }

  testWidgets('an empty name cannot be saved', (tester) async {
    await open(tester);

    expect(canSave(tester), isFalse);
    expect(find.text(Errors.albumNameHasSlash), findsNothing);
    expect(find.text(Errors.albumNameTaken), findsNothing);
  });

  testWidgets('another case of its own name saves on rename', (tester) async {
    final results = await open(
      tester,
      initial: 'Trips',
      isNameTaken: (name) => name.toLowerCase() == 'japan',
    );

    await tester.enterText(field, 'TRIPS ');
    await tester.pump();
    expect(canSave(tester), isTrue);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(results, ['TRIPS']);
  });
}
