import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/chat/chat_attachment_preview.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A 1x1 transparent PNG.
final Uint8List _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82,
]);

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('draws the decrypted image', (tester) async {
    await _pump(
      tester,
      SizedBox(
        width: 120,
        height: 80,
        child: ChatAttachmentPreview(load: () async => _png),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as MemoryImage).bytes, _png);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no frame leaves the preview blank', (tester) async {
    await _pump(
      tester,
      SizedBox(
        width: 120,
        height: 80,
        child: ChatAttachmentPreview(
          load: () async => null,
          reportFailure: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(QuarkIcons.image_outlined), findsNothing);
    expect(find.byType(QuarkLoader), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed load shows the image glyph', (tester) async {
    await _pump(
      tester,
      SizedBox(
        width: 120,
        height: 80,
        child: ChatAttachmentPreview(load: () async => throw Exception('nope')),
      ),
    );
    await tester.pump();

    expect(find.byIcon(QuarkIcons.image_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
