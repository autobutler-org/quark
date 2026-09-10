import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/svg_viewer_page.dart';

/// #1806: `.svg` used to be classified as `image` and pushed into the photo
/// viewer, whose `Image.memory` cannot decode XML — every SVG rendered as a
/// broken image. It now gets its own viewer, which renders through
/// [SvgPicture].
void main() {
  final bytes = Uint8List.fromList(
    utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
      '<rect width="10" height="10"/></svg>',
    ),
  );

  testWidgets('renders the SVG and its name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SvgViewerPage(bytes: bytes, name: 'logo.svg'),
      ),
    );
    // The decode is async; settling would wait on it forever.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('logo.svg'), findsOneWidget);
  });
}
