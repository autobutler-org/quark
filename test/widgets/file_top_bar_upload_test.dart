import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/file_browser/file_top_bar.dart';

/// Folder upload gets no button of its own (#1615): to the user "upload" is
/// one action, and whether they picked a file or a folder is a property of
/// what they chose. The platform still forces a choice — no picker we can
/// reach offers files and folders in one pass — so it lives inside the Upload
/// action rather than beside it in the toolbar.
///
/// iOS adds Photos as a third source (#1797): its document picker is the
/// Files app and cannot see the Camera Roll, so Photos is listed first.
void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required VoidCallback onUpload,
    VoidCallback? onUploadPhotos,
    VoidCallback? onUploadFolder,
    VoidCallback? onCancelUpload,
    bool isUploading = false,
    int uploadTotal = 0,
    int uploadCompleted = 0,
  }) async {
    // Wide enough that the bar lays out its full action row rather than a
    // compact variant.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileTopBar(
            currentPath: '/docs',
            isGridView: false,
            isUnifiedView: false,
            onToggleUnifiedView: () {},
            isSearchMode: false,
            isUploading: isUploading,
            uploadTotal: uploadTotal,
            uploadCompleted: uploadCompleted,
            isCreatingFolder: false,
            isRefreshing: false,
            onGoHome: () {},
            onGoUp: () {},
            onToggleView: () {},
            onSearchChanged: (_) {},
            onSearchClosed: () {},
            onRefresh: () {},
            onUploadPressed: onUpload,
            onUploadPhotosPressed: onUploadPhotos,
            onUploadFolderPressed: onUploadFolder,
            onCancelUploadPressed: onCancelUpload,
            onCreateFolderPressed: () {},
            onNewFilePressed: () {},
            onOpenDrawer: () {},
            onOpenSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the toolbar never grows a second upload button', (tester) async {
    await pumpBar(tester, onUpload: () {}, onUploadFolder: () {});

    expect(find.text('Upload'), findsOneWidget);
    // No "Upload folder" sitting next to it, and no chooser until asked for.
    expect(find.text('Upload folder'), findsNothing);
    expect(find.byType(MenuItemButton), findsNothing);
  });

  testWidgets('Upload offers files and folders where folders are supported', (
    tester,
  ) async {
    var files = 0;
    var folders = 0;
    await pumpBar(
      tester,
      onUpload: () => files++,
      onUploadFolder: () => folders++,
    );

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    // widgetWithText, not text: the bar has its own "Files" branding and a
    // "New folder" chip, so the assertion has to name the menu.
    expect(find.widgetWithText(MenuItemButton, 'Files'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, 'Folder'), findsOneWidget);
    expect(files, 0, reason: 'opening the chooser must not start an upload');

    await tester.tap(find.widgetWithText(MenuItemButton, 'Folder'));
    await tester.pumpAndSettle();
    expect(folders, 1);
    expect(files, 0);
  });

  testWidgets('Files in the chooser runs the ordinary file upload', (
    tester,
  ) async {
    var files = 0;
    await pumpBar(tester, onUpload: () => files++, onUploadFolder: () {});

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Files'));
    await tester.pumpAndSettle();

    expect(files, 1);
  });

  testWidgets('without extra sources Upload goes straight to files', (
    tester,
  ) async {
    // Android / desktop-without-folder: the chooser would only ever offer
    // one real option. Upload behaves exactly as it always has.
    var files = 0;
    await pumpBar(tester, onUpload: () => files++);

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    expect(files, 1);
    expect(find.byType(MenuItemButton), findsNothing);
  });

  testWidgets('iOS Upload offers Photos first, then Files', (tester) async {
    var photos = 0;
    var files = 0;
    await pumpBar(
      tester,
      onUpload: () => files++,
      onUploadPhotos: () => photos++,
    );

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(MenuItemButton, 'Photos'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, 'Files'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, 'Folder'), findsNothing);
    expect(photos, 0, reason: 'opening the chooser must not start an upload');
    expect(files, 0);

    await tester.tap(find.widgetWithText(MenuItemButton, 'Photos'));
    await tester.pumpAndSettle();
    expect(photos, 1);
    expect(files, 0);
  });

  testWidgets('Photos sits above Files when folders are also offered', (
    tester,
  ) async {
    await pumpBar(
      tester,
      onUpload: () {},
      onUploadPhotos: () {},
      onUploadFolder: () {},
    );

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(MenuItemButton, 'Photos'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, 'Files'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, 'Folder'), findsOneWidget);

    final photosY = tester
        .getTopLeft(find.widgetWithText(MenuItemButton, 'Photos'))
        .dy;
    final filesY = tester
        .getTopLeft(find.widgetWithText(MenuItemButton, 'Files'))
        .dy;
    final folderY = tester
        .getTopLeft(find.widgetWithText(MenuItemButton, 'Folder'))
        .dy;
    expect(photosY, lessThan(filesY));
    expect(filesY, lessThan(folderY));
  });

  testWidgets('an upload in flight cannot start another', (tester) async {
    var files = 0;
    var folders = 0;
    await pumpBar(
      tester,
      onUpload: () => files++,
      onUploadFolder: () => folders++,
      isUploading: true,
      uploadTotal: 100,
      uploadCompleted: 12,
    );

    // The chip shows progress instead of offering another upload.
    expect(find.text('Upload'), findsNothing);
    expect(find.text('12/100'), findsOneWidget);
    expect(files, 0);
    expect(folders, 0);
  });

  testWidgets('an upload in flight can still be cancelled', (tester) async {
    // A batch failing its way through a large folder must not leave the user
    // watching a disabled button with no way out.
    var cancels = 0;
    var files = 0;
    await pumpBar(
      tester,
      onUpload: () => files++,
      onUploadPhotos: () {},
      onUploadFolder: () {},
      onCancelUpload: () => cancels++,
      isUploading: true,
      uploadTotal: 100,
      uploadCompleted: 12,
    );

    await tester.tap(find.text('12/100'));
    await tester.pumpAndSettle();

    // Cancel, and nothing that would start more work.
    expect(
      find.widgetWithText(MenuItemButton, 'Cancel upload'),
      findsOneWidget,
    );
    expect(find.widgetWithText(MenuItemButton, 'Photos'), findsNothing);
    expect(find.widgetWithText(MenuItemButton, 'Files'), findsNothing);
    expect(find.widgetWithText(MenuItemButton, 'Folder'), findsNothing);

    await tester.tap(find.widgetWithText(MenuItemButton, 'Cancel upload'));
    await tester.pumpAndSettle();

    expect(cancels, 1);
    expect(files, 0);
  });

  testWidgets('with no cancel handler the chip stays inert while uploading', (
    tester,
  ) async {
    var files = 0;
    await pumpBar(
      tester,
      onUpload: () => files++,
      onUploadFolder: () {},
      isUploading: true,
      uploadTotal: 100,
      uploadCompleted: 12,
    );

    await tester.tap(find.text('12/100'));
    await tester.pumpAndSettle();

    expect(find.byType(MenuItemButton), findsNothing);
    expect(files, 0);
  });
}
