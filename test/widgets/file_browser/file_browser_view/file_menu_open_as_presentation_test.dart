import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/file_browser_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

FileNode _node(String path, {bool isDir = false}) => FileNode(
  name: path.split('/').last,
  size: 0,
  isDir: isDir,
  deviceName: '',
  devicePath: '',
  deviceSerial: 'SN1',
  dirPath: path,
);

/// The Files menu offers "Open as presentation" on a PowerPoint file: the
/// Quark imports it beside itself and the new presentation opens (#1171).
void main() {
  late List<(String, String?)> imported;
  late Object? failure;

  setUp(() {
    imported = [];
    failure = null;
  });

  Future<GoRouter> openMenu(
    WidgetTester tester,
    FileNode item, {
    bool inArchive = false,
  }) async {
    final controller = FileBrowserController(
      importPowerPoint: (path, {serial}) async {
        imported.add((path, serial));
        final f = failure;
        if (f != null) throw f;
        return (
          path: 'talks/Talk.qslide',
          slides: 2,
          warnings: const <({int slide, String message})>[],
        );
      },
    );
    final router = GoRouter(
      initialLocation: AppRoutes.files,
      routes: [
        GoRoute(
          path: AppRoutes.files,
          builder: (_, _) => Scaffold(
            body: FileMenuButton(
              menu: FileMenu(
                item: item,
                menuActions: FileBrowserView.defaultMenuActions,
                extractingPaths: const {},
                inArchive: inArchive,
                isSearchMode: false,
                onDispatchMenuAction: (context, node, action) =>
                    controller.handleFileAction(
                      node: node,
                      action: action,
                      context: context,
                    ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '${AppRoutes.slides}/:path(.*)',
          builder: (_, state) => Text('editor ${state.pathParameters['path']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(QuarkIcons.more_vert));
    await tester.pumpAndSettle();
    return router;
  }

  for (final name in ['Talk.pptx', 'Talk.pptm', 'Show.PPSX']) {
    testWidgets('imports $name in place and opens the presentation', (
      tester,
    ) async {
      final router = await openMenu(tester, _node('talks/$name'));
      await tester.tap(
        find.byKey(const ValueKey('file_menu_openAsPresentation')),
      );
      await tester.pumpAndSettle();

      expect(imported, [('talks/$name', 'SN1')]);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/slides/talks/Talk.qslide?serial=SN1',
      );
    });
  }

  testWidgets('a refused import says why and stays put', (tester) async {
    failure = const ApiException(400);
    final router = await openMenu(tester, _node('talks/Talk.pptx'));
    await tester.tap(find.text('Open as presentation'));
    await tester.pumpAndSettle();
    expect(find.text(Errors.unreadablePowerPoint), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutes.files,
    );
  });

  for (final (why, item, inArchive) in [
    ('a legacy .ppt', _node('talks/Old.ppt'), false),
    ('a file that is not PowerPoint', _node('docs/notes.txt'), false),
    ('a folder', _node('Talk.pptx', isDir: true), false),
    ('a file inside an archive', _node('talks/Talk.pptx'), true),
  ]) {
    testWidgets('is not offered on $why', (tester) async {
      await openMenu(tester, item, inArchive: inArchive);
      expect(find.text('Open as presentation'), findsNothing);
    });
  }
}
