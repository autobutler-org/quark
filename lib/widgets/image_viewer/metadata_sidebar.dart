import 'package:material_ui/material_ui.dart';
import 'package:quark/models/photo_metadata.dart';
import 'package:quark/widgets/image_viewer/metadata_content.dart';

/// The photo viewer's metadata panel on desktop.
class MetadataSidebar extends StatelessWidget {
  final String name;

  /// The file's size in bytes when known, for a photo without metadata.
  final int? fileSize;

  final PhotoMetadata? metadata;
  final bool loading;
  final void Function(AlbumRef album) onAlbumTap;

  const MetadataSidebar({
    super.key,
    required this.name,
    this.fileSize,
    required this.metadata,
    required this.loading,
    required this.onAlbumTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111111),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: _buildSections(context),
      ),
    );
  }

  List<Widget> _buildSections(BuildContext context) => MetadataContent.sections(
    context: context,
    name: name,
    fileSize: fileSize,
    metadata: metadata,
    loading: loading,
    onAlbumTap: onAlbumTap,
  );
}
