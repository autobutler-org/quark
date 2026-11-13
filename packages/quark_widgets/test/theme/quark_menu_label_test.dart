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
        style: const MenuStyle(
          minimumSize: WidgetStatePropertyAll(Size(280, 0)),
        ),
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

  testWidgets('a menu drops from the left edge of its chip', (tester) async {
    await pumpAt(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: MenuAnchor(
          alignmentOffset: QuarkBarIconButton.menuAnchorOffset,
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
                label: const Text('Folder'),
              ),
            ),
          ],
          builder: (context, menu, _) => QuarkBarChip(
            key: const ValueKey('upload'),
            icon: QuarkIcons.upload_rounded,
            label: 'Upload',
            onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          ),
        ),
      ),
      brightness: Brightness.dark,
      size: const Size(800, 600),
    );
    await tester.tap(find.byKey(const ValueKey('upload')));
    await tester.pumpAndSettle();
    final chip = tester.getRect(find.byType(OutlinedButton));
    late Rect panel;
    tester.element(find.text('Files')).visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is Material &&
          widget.shape is RoundedRectangleBorder &&
          (widget.color?.a ?? 0) > 0) {
        final box = ancestor.renderObject! as RenderBox;
        panel = box.localToGlobal(Offset.zero) & box.size;
        return false;
      }
      return true;
    });
    expect(panel.left, chip.left);
  });
}
