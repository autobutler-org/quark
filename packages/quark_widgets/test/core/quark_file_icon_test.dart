import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testWidgets('renders a folder glyph for a folder', (tester) async {
    await pumpAt(tester, const QuarkFileIcon(kind: QuarkFileKind.folder));

    expect(find.byIcon(QuarkIcons.folder_outlined), findsOneWidget);
  });

  test('maps each kind to its glyph', () {
    expect(
      QuarkFileIcon.iconFor(QuarkFileKind.folder),
      QuarkIcons.folder_outlined,
    );
    expect(
      QuarkFileIcon.iconFor(QuarkFileKind.image),
      QuarkIcons.image_outlined,
    );
    expect(
      QuarkFileIcon.iconFor(QuarkFileKind.video),
      QuarkIcons.video_file_outlined,
    );
    expect(
      QuarkFileIcon.iconFor(QuarkFileKind.audio),
      QuarkIcons.audio_file_outlined,
    );
    expect(
      QuarkFileIcon.iconFor(QuarkFileKind.pdf),
      QuarkIcons.picture_as_pdf_outlined,
    );
    expect(
      QuarkFileIcon.iconFor(QuarkFileKind.archive),
      QuarkIcons.archive_outlined,
    );
    expect(QuarkFileIcon.iconFor(QuarkFileKind.qdoc), QuarkIcons.edit_document);
    expect(QuarkFileIcon.iconFor(QuarkFileKind.qsheet), QuarkIcons.table_chart);
    expect(QuarkFileIcon.iconFor(QuarkFileKind.qslide), QuarkIcons.slideshow);
    expect(
      QuarkFileIcon.iconFor(QuarkFileKind.document),
      QuarkIcons.description_outlined,
    );
    expect(
      QuarkFileIcon.iconFor(QuarkFileKind.spreadsheet),
      QuarkIcons.table_chart_outlined,
    );
    expect(
      QuarkFileIcon.iconFor(QuarkFileKind.presentation),
      QuarkIcons.slideshow_outlined,
    );
    expect(
      QuarkFileIcon.iconFor(QuarkFileKind.generic),
      QuarkIcons.insert_drive_file_outlined,
    );
  });
}
