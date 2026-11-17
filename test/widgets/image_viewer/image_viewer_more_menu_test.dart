import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/image_viewer/image_viewer_more_menu.dart';

/// #3436: the viewer's menu copies the photo to the clipboard, apart from
/// duplicating it on the Quark.
void main() {
  ImageViewerMoreMenu menu({
    required List<String> events,
    String? relPath = 'Photos/beach.jpg',
    String? copyUnavailableReason,
    VoidCallback? onDownloadAsJpeg,
  }) => ImageViewerMoreMenu(
    includeBarActions: false,
    isFavorite: false,
    sidebarOpen: false,
    relPath: relPath,
    sourceAlbum: null,
    onToggleFavorite: () {},
    onRotate: () {},
    onDownload: () {},
    onToggleSidebar: () {},
    onAddToAlbum: () {},
    onRemoveFromAlbum: () {},
    onCopy: () => events.add('copy'),
    copyUnavailableReason: copyUnavailableReason,
    onDuplicate: () => events.add('duplicate'),
    onShare: () {},
    onDelete: () {},
    onDownloadAsJpeg: onDownloadAsJpeg,
  );

  QuarkMenuEntry entryOf(ImageViewerMoreMenu m, String id) =>
      m.entries.firstWhere((e) => e.key == ValueKey('image_viewer_more_$id'));

  test('offers Copy and Duplicate, each running its own', () {
    final events = <String>[];
    final m = menu(events: events);

    final copy = entryOf(m, 'copy');
    final duplicate = entryOf(m, 'duplicate');
    expect(copy.label, 'Copy');
    expect(duplicate.label, 'Duplicate');

    copy.onSelected!();
    duplicate.onSelected!();
    expect(events, ['copy', 'duplicate']);
  });

  test('disables Copy where the clipboard takes no image', () {
    final m = menu(
      events: <String>[],
      copyUnavailableReason: 'Copying a photo works in the web app for now',
    );

    expect(entryOf(m, 'copy').onSelected, isNull);
    expect(entryOf(m, 'duplicate').onSelected, isNotNull);
  });

  test('a device photo has neither', () {
    final m = menu(events: <String>[], relPath: null);

    expect(m.entries, isEmpty);
  });

  test('a HEIC photo offers Download as JPEG (#4188)', () {
    final events = <String>[];
    final m = menu(
      events: events,
      relPath: 'Photos/IMG_0001.HEIC',
      onDownloadAsJpeg: () => events.add('download_jpeg'),
    );

    final jpeg = entryOf(m, 'download_jpeg');
    expect(jpeg.label, 'Download as JPEG');
    jpeg.onSelected!();
    expect(events, ['download_jpeg']);
  });

  test('without a JPEG action there is no such entry (#4188)', () {
    final m = menu(events: <String>[]);

    expect(
      m.entries.where(
        (e) => e.key == const ValueKey('image_viewer_more_download_jpeg'),
      ),
      isEmpty,
    );
  });
}
