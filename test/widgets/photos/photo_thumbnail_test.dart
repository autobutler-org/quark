import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/photos/photo_thumbnail.dart';

/// #2603: the photo tile around a thumbnail is the button a screen reader
/// names; the picture inside it adds nothing to say, so it stays out of the
/// semantics tree rather than turning the tile into an unlabeled image.
void main() {
  for (final (label, thumbnail) in [
    ('a Quark photo', PhotoThumbnail(url: Uri.parse('http://quark/t.jpg'))),
    (
      'a Quark photo that can backfill',
      PhotoThumbnail(
        url: Uri.parse('http://quark/t.jpg'),
        path: '/photos/t.heic',
      ),
    ),
    (
      'a sample photo',
      PhotoThumbnail(
        url: Uri(scheme: 'asset', path: 'assets/demo/aurora.jpg'),
      ),
    ),
  ]) {
    testWidgets('$label is not announced as an image', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: Semantics(
              container: true,
              button: true,
              label: 'beach.jpg',
              child: SizedBox.square(dimension: 100, child: thumbnail),
            ),
          ),
        ),
      );

      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        expect(image.excludeFromSemantics, isTrue);
      }
      expect(find.byType(Image), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('beach.jpg'))
            .flagsCollection
            .isImage,
        isFalse,
      );
      handle.dispose();
    });
  }
}
