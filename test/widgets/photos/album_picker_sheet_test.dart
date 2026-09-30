import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/photos/album_picker_sheet.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The album picker host (#2585): it shows the package picker in the shared
/// sheet, titled with how many photos are going in, and its close button
/// answers null without picking.
void main() {
  for (final (count, title) in [
    (1, 'Add 1 photo to...'),
    (3, 'Add 3 photos to...'),
  ]) {
    testWidgets('titles the sheet for $count and closes without a pick', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final picks = <AlbumItem?>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => picks.add(
                  await AlbumPickerSheetHost.show(
                    context,
                    selectedCount: count,
                    loadAlbums: () async => const [
                      AlbumItem(id: 1, name: 'Trips'),
                    ],
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(title), findsOneWidget);
      expect(find.byKey(const ValueKey('album_picker_1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('quark_sheet_close')));
      await tester.pumpAndSettle();
      expect(picks, [null]);
    });
  }
}
