import 'package:flutter/material.dart';
import 'package:quark/models/photo_metadata.dart';
import 'package:quark/widgets/image_viewer/metadata_content.dart';

/// The photo viewer's metadata panel on mobile, dragged up from the bottom.
class MetadataDrawer extends StatelessWidget {
  final ScrollController scrollController;
  final String name;
  final PhotoMetadata? metadata;
  final bool loading;
  final void Function(AlbumRef album) onAlbumTap;

  const MetadataDrawer({
    super.key,
    required this.scrollController,
    required this.name,
    required this.metadata,
    required this.loading,
    required this.onAlbumTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              children: MetadataContent.sections(
                context: context,
                name: name,
                metadata: metadata,
                loading: loading,
                onAlbumTap: onAlbumTap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
