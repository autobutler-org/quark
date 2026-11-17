import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/clipboard_utils.dart';

/// #3436: copying a photo puts a PNG on the clipboard and says so.
void main() {
  Future<Uint8List> png(int width, int height) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF008080),
    );
    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Future<BuildContext> pump(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return context;
  }

  testWidgets('writes a PNG and confirms it', (tester) async {
    final context = await pump(tester);
    Uint8List? written;
    final photo = (await tester.runAsync(() => png(10, 10)))!;

    await tester.runAsync(
      () => copyPhotoToClipboard(
        context,
        () async => photo,
        writer: (bytes) async => written = await bytes,
      ),
    );
    await tester.pump();

    expect(written, isNotNull);
    expect(written!.sublist(1, 4), 'PNG'.codeUnits);
    expect(find.text('Copied to clipboard'), findsOneWidget);
  });

  testWidgets('says it could not copy when the photo fails to load', (
    tester,
  ) async {
    final context = await pump(tester);

    await tester.runAsync(
      () => copyPhotoToClipboard(
        context,
        () async => throw Exception('boom'),
        writer: (bytes) async => await bytes,
      ),
    );
    await tester.pump();

    expect(find.textContaining("Couldn't copy the photo"), findsOneWidget);
    expect(find.text('Copied to clipboard'), findsNothing);
    expect(find.textContaining('boom'), findsNothing);
  });

  testWidgets('shows why where the platform takes no image', (tester) async {
    final context = await pump(tester);
    var loaded = false;

    await copyPhotoToClipboard(context, () async {
      loaded = true;
      return null;
    });
    await tester.pump();

    // Tests run natively, where there is no image clipboard yet.
    expect(isImageClipboardAvailable, isFalse);
    expect(find.text(imageClipboardUnavailableReason!), findsOneWidget);
    expect(loaded, isFalse);
  });
}
