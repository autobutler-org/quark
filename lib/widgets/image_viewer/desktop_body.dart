import 'package:material_ui/material_ui.dart';
import 'package:quark/models/photo_metadata.dart';
import 'package:quark/widgets/image_viewer/metadata_sidebar.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The photo viewer at desktop widths: the photo, with the metadata sidebar
/// beside it in a [QuarkResizablePane] that slides in and out, resizes from
/// its inner edge, and hides when dragged below its min width (#4294).
///
/// Whether the sidebar shows and how wide it is are the page's:
/// [sidebarOpen] and [sidebarWidth] in, [onSidebarOpenChanged] and
/// [onSidebarWidthChanged] out.
///
/// Key prefixes: [QuarkResizablePane]'s, with the id `photo_viewer`.
class DesktopBody extends StatelessWidget {
  /// The sidebar's width before the user resizes it.
  static const double defaultSidebarWidth = 288;

  final Widget photoArea;
  final bool sidebarOpen;

  /// The sidebar's open width.
  final double sidebarWidth;

  /// Fires with the sidebar's new width as its edge is dragged.
  final ValueChanged<double> onSidebarWidthChanged;

  /// Fires with false when the sidebar is dragged below its min width, and
  /// with true when it is dragged back out.
  final ValueChanged<bool> onSidebarOpenChanged;

  final String name;

  /// The file's size in bytes when known, for a photo without metadata.
  final int? fileSize;

  final PhotoMetadata? metadata;
  final bool loading;
  final void Function(AlbumRef album) onAlbumTap;

  const DesktopBody({
    super.key,
    required this.photoArea,
    required this.sidebarOpen,
    required this.sidebarWidth,
    required this.onSidebarWidthChanged,
    required this.onSidebarOpenChanged,
    required this.name,
    this.fileSize,
    required this.metadata,
    required this.loading,
    required this.onAlbumTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: photoArea),
        QuarkResizablePane(
          id: 'photo_viewer',
          semanticLabel: 'Resize photo details',
          edge: QuarkPaneEdge.end,
          width: sidebarWidth,
          defaultWidth: defaultSidebarWidth,
          isCollapsed: !sidebarOpen,
          onWidthChanged: onSidebarWidthChanged,
          onCollapsedChanged: (collapsed) => onSidebarOpenChanged(!collapsed),
          child: MetadataSidebar(
            name: name,
            fileSize: fileSize,
            metadata: metadata,
            loading: loading,
            onAlbumTap: onAlbumTap,
          ),
        ),
      ],
    );
  }
}
