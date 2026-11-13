import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// A menu row lines its glyph up with the label the way a bar chip does.
void main() {
  testWidgets('icons share a column and labels share a left edge', (
    tester,
  ) async {
    await pumpAt(
      tester,
      MenuAnchor(
        menuChildren: [
          MenuItemButton(
            onPressed: () {},
            child: quarkMenuLabel(
              leading: const Icon(QuarkIcons.upload_rounded),
              label: const Text('Files'),
            ),
          ),
          MenuItemButton(
            onPressed: () {},
            child: quarkMenuLabel(
              leading: const Icon(QuarkIcons.drive_folder_upload_outlined),
              trailing: const Icon(QuarkIcons.check),
              label: const Text('Folder'),
            ),
          ),
        ],
        builder: (context, menu, _) =>
            TextButton(onPressed: menu.open, child: const Text('Open')),
      ),
      brightness: Brightness.dark,
      size: const Size(400, 400),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final filesIcon = tester.getRect(find.byIcon(QuarkIcons.upload_rounded));
    final folderIcon = tester.getRect(
      find.byIcon(QuarkIcons.drive_folder_upload_outlined),
    );
    final files = tester.getRect(find.text('Files'));
    final folder = tester.getRect(find.text('Folder'));
    final check = tester.getRect(find.byIcon(QuarkIcons.check));

    expect(filesIcon.left, folderIcon.left);
    expect(filesIcon.width, quarkMenuIconSize);
    expect(folderIcon.width, quarkMenuIconSize);
    expect(files.left, folder.left);
    expect(files.left - filesIcon.right, quarkMenuIconGap);
    expect(folder.left - folderIcon.right, quarkMenuIconGap);
    expect(filesIcon.center.dy, closeTo(files.center.dy, 1));
    expect(folderIcon.center.dy, closeTo(folder.center.dy, 1));
    expect(check.center.dy, closeTo(folder.center.dy, 1));

    final filesGlyphs =
        (tester.renderObject(find.text('Files')) as RenderParagraph)
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 5),
            );
    expect(filesGlyphs.single.left, lessThan(2));
  });
}
