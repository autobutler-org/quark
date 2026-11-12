import 'package:material_ui/material_ui.dart';
import 'package:quark/models/photo_metadata.dart';
import 'package:quark/widgets/image_viewer/metadata_sidebar.dart';

const _kSidebarWidth = 288.0;

/// The photo viewer at desktop widths: the photo, with the metadata sidebar
/// sliding in beside it.
class DesktopBody extends StatelessWidget {
  final Widget photoArea;
  final bool sidebarOpen;
  final String name;
  final PhotoMetadata? metadata;
  final bool loading;
  final void Function(AlbumRef album) onAlbumTap;

  const DesktopBody({
    super.key,
    required this.photoArea,
    required this.sidebarOpen,
    required this.name,
    required this.metadata,
    required this.loading,
    required this.onAlbumTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: photoArea),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: sidebarOpen
              ? SizedBox(
                  width: _kSidebarWidth,
                  child: MetadataSidebar(
                    name: name,
                    metadata: metadata,
                    loading: loading,
                    onAlbumTap: onAlbumTap,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
