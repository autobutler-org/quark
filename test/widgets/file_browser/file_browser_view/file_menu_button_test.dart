import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu_button.dart';
import 'package:quark_icons/quark_icons.dart';

FileNode _folder(String path, {String serial = ''}) => FileNode(
  name: '${path.split('/').last}/',
  size: 0,
  isDir: true,
  deviceName: '',
  devicePath: '',
  deviceSerial: serial,
  dirPath: path,
);

/// Opens [item]'s menu and returns the entries it offers.
Future<List<String>> _menuFor(
  WidgetTester tester,
  FileNode item, {
  bool isAdmin = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FileMenuButton(
          item: item,
          menuActions: FileBrowserView.defaultMenuActions,
          extractingPaths: const {},
          inArchive: false,
          isSearchMode: false,
          isAdmin: isAdmin,
          onDispatchMenuAction: (_, _, _) {},
        ),
      ),
    ),
  );
  await tester.tap(find.byIcon(QuarkIcons.more_vert));
  await tester.pumpAndSettle();
  return tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(PopupMenuItem<FileMenuAction>),
          matching: find.byType(Text),
        ),
      )
      .map((t) => t.data!)
      .toList();
}

/// A member may not move or delete a home or group folder itself (#2016), so
/// the menu does not offer to; the Quark refuses it either way. Nobody is
/// offered Share on the `users` or `groups` folder, since a grant there would
/// expose every home or every group folder.
void main() {
  testWidgets("hides Move/Rename and Delete on a member's home", (
    tester,
  ) async {
    expect(await _menuFor(tester, _folder('users/bob')), [
      'Download',
      'Share…',
    ]);
  });

  testWidgets('offers only Download on the users folder to a member', (
    tester,
  ) async {
    expect(await _menuFor(tester, _folder('users')), ['Download']);
  });

  testWidgets('keeps them on the users folder for an admin, without Share', (
    tester,
  ) async {
    expect(await _menuFor(tester, _folder('users'), isAdmin: true), [
      'Download',
      'Move/Rename',
      'Delete',
    ]);
  });

  testWidgets('offers Share on a users folder on a USB drive', (tester) async {
    expect(await _menuFor(tester, _folder('users', serial: 'USB1')), [
      'Download',
      'Move/Rename',
      'Share…',
      'Delete',
    ]);
  });

  testWidgets('keeps them on what is inside a home', (tester) async {
    expect(await _menuFor(tester, _folder('users/bob/Documents')), [
      'Download',
      'Move/Rename',
      'Share…',
      'Delete',
    ]);
  });

  testWidgets('keeps them on a home for an admin', (tester) async {
    expect(await _menuFor(tester, _folder('users/bob'), isAdmin: true), [
      'Download',
      'Move/Rename',
      'Share…',
      'Delete',
    ]);
  });

  testWidgets('keeps them on users/<name> on a USB drive', (tester) async {
    expect(await _menuFor(tester, _folder('users/bob', serial: 'USB1')), [
      'Download',
      'Move/Rename',
      'Share…',
      'Delete',
    ]);
  });

  testWidgets("hides Move/Rename and Delete on a member's group folder", (
    tester,
  ) async {
    expect(await _menuFor(tester, _folder('groups/Family')), [
      'Download',
      'Share…',
    ]);
  });

  testWidgets('offers only Download on the groups folder to a member', (
    tester,
  ) async {
    expect(await _menuFor(tester, _folder('groups')), ['Download']);
  });

  testWidgets('keeps them on the groups folder for an admin, without Share', (
    tester,
  ) async {
    expect(await _menuFor(tester, _folder('groups'), isAdmin: true), [
      'Download',
      'Move/Rename',
      'Delete',
    ]);
  });

  testWidgets('keeps them on what is inside a group folder', (tester) async {
    expect(await _menuFor(tester, _folder('groups/Family/Photos')), [
      'Download',
      'Move/Rename',
      'Share…',
      'Delete',
    ]);
  });

  testWidgets('keeps them on a group folder for an admin', (tester) async {
    expect(await _menuFor(tester, _folder('groups/Family'), isAdmin: true), [
      'Download',
      'Move/Rename',
      'Share…',
      'Delete',
    ]);
  });

  testWidgets('keeps them on groups/<name> on a USB drive', (tester) async {
    expect(await _menuFor(tester, _folder('groups/Family', serial: 'USB1')), [
      'Download',
      'Move/Rename',
      'Share…',
      'Delete',
    ]);
  });
}
