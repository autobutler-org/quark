import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/svg_viewer_page.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #1806: `.svg` used to be classified as `image` and pushed into the photo
/// viewer, whose `Image.memory` cannot decode XML — every SVG rendered as a
/// broken image. It now gets its own viewer, which renders through
/// [SvgPicture].
void main() {
  Uint8List svg(String markup) => Uint8List.fromList(utf8.encode(markup));

  final bytes = svg(
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
    '<rect width="10" height="10"/></svg>',
  );

  /// Pumps the viewer over [bytes] and waits out the real, off-zone decode.
  Future<void> pumpViewer(WidgetTester tester, Uint8List bytes) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SvgViewerPage(bytes: bytes, name: 'logo.svg'),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  final unreadable = find.text(Errors.couldNot('show this SVG'));

  // What the decoder builds once it has a picture; a failed decode builds none.
  final artwork = find.descendant(
    of: find.byType(SvgPicture),
    matching: find.byType(FittedBox),
  );

  testWidgets('renders the SVG and its name', (tester) async {
    await pumpViewer(tester, bytes);

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('logo.svg'), findsOneWidget);
    expect(artwork, findsOneWidget);
  });

  // #2989: a 10 pixel icon used to be drawn at 10 pixels in the middle of the
  // screen. Vector artwork has no native resolution to respect.
  testWidgets('scales small artwork up to the viewport', (tester) async {
    await pumpViewer(tester, bytes);

    final body = tester.getSize(find.byType(QuarkCheckerboard));
    expect(tester.getSize(find.byType(SvgPicture)), body);
  });

  // #2989: markup that is not an SVG threw out of the decoder and left the
  // checkerboard empty.
  testWidgets('says so when the markup cannot be parsed', (tester) async {
    await pumpViewer(tester, svg('<svg><rect'));

    expect(unreadable, findsOneWidget);
    expect(artwork, findsNothing);
    expect(tester.takeException(), isNull);
  });

  // #2989: an SVG with no viewBox, width or height is valid — a browser gives
  // it 300x150 — but the decoder refuses it.
  testWidgets('renders an SVG that declares no size', (tester) async {
    await pumpViewer(
      tester,
      svg(
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<rect width="10" height="10"/></svg>',
      ),
    );

    expect(artwork, findsOneWidget);
    expect(unreadable, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders an SVG sized in percentages', (tester) async {
    await pumpViewer(
      tester,
      svg(
        '<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%">'
        '<rect width="10" height="10"/></svg>',
      ),
    );

    expect(artwork, findsOneWidget);
    expect(unreadable, findsNothing);
    expect(tester.takeException(), isNull);
  });

  // A script is never run and an external reference never fetched: the
  // artwork around them still renders.
  testWidgets('ignores scripts and external references', (tester) async {
    await pumpViewer(
      tester,
      svg(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'xmlns:xlink="http://www.w3.org/1999/xlink" width="10" height="10">'
        '<script>alert(1)</script>'
        '<image width="10" height="10" href="https://example.com/a.png"/>'
        '<use xlink:href="https://example.com/b.svg#x"/>'
        '<rect width="10" height="10" onclick="alert(1)"/></svg>',
      ),
    );

    expect(artwork, findsOneWidget);
    expect(unreadable, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
