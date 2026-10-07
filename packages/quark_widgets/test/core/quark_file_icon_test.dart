import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('renders the glyph for the name it is given', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkFileIcon(name: 'holiday.jpg', isDir: false),
      size: size,
    );

    expect(find.byIcon(QuarkIcons.image_outlined), findsOneWidget);
  });

  testBothViewports('renders a folder glyph for a directory', (
    tester,
    size,
  ) async {
    // The directory flag wins even when the name looks like a file.
    await pumpAt(
      tester,
      const QuarkFileIcon(name: 'archive.zip', isDir: true),
      size: size,
    );

    expect(find.byIcon(QuarkIcons.folder_outlined), findsOneWidget);
  });

  testWidgets('honors size and color', (tester) async {
    await pumpAt(
      tester,
      const QuarkFileIcon(
        name: 'notes.txt',
        isDir: false,
        size: 48,
        color: Color(0xFF00FF00),
      ),
      size: narrowViewport,
    );

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.size, 48);
    expect(icon.color, const Color(0xFF00FF00));
  });

  test('maps each family of extensions to its glyph', () {
    IconData iconFor(String name) => QuarkFileIcon.iconFor(name, isDir: false);

    expect(iconFor('a.HEIC'), QuarkIcons.image_outlined);
    expect(iconFor('a.mkv'), QuarkIcons.video_file_outlined);
    expect(iconFor('a.flac'), QuarkIcons.audio_file_outlined);
    expect(iconFor('a.pdf'), QuarkIcons.picture_as_pdf_outlined);
    expect(iconFor('a.zst'), QuarkIcons.archive_outlined);
    expect(iconFor('a.qdoc'), QuarkIcons.edit_document);
    expect(iconFor('a.qsheet'), QuarkIcons.table_chart);
    expect(iconFor('a.qslide'), QuarkIcons.slideshow);
    expect(iconFor('a.docx'), QuarkIcons.description_outlined);
    expect(iconFor('a.csv'), QuarkIcons.table_chart_outlined);
    expect(iconFor('a.pptx'), QuarkIcons.slideshow_outlined);
    expect(iconFor('a.unknown'), QuarkIcons.insert_drive_file_outlined);
    expect(iconFor('no-extension'), QuarkIcons.insert_drive_file_outlined);
  });
}
