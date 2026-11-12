import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/models/photo_metadata.dart';
import 'package:quark/widgets/image_viewer/metadata_content.dart';

/// The photo viewer's metadata panel on mobile, dragged up from the bottom.
///
/// Both the handle strip (`photo_info_handle`) and the rows drag the sheet,
/// with a finger or a mouse (#3359): the rows through [scrollController],
/// the handle, which is not part of the list, through [onHandleDrag] and
/// [onHandleDragEnd].
class MetadataDrawer extends StatelessWidget {
  final ScrollController scrollController;
  final String name;
  final PhotoMetadata? metadata;
  final bool loading;
  final void Function(AlbumRef album) onAlbumTap;

  /// Called as the handle is dragged, with how far it moved down, in logical
  /// pixels; negative is up.
  final ValueChanged<double> onHandleDrag;

  /// Called when a handle drag ends, with its vertical velocity in logical
  /// pixels per second; negative is up.
  final ValueChanged<double> onHandleDragEnd;

  const MetadataDrawer({
    super.key,
    required this.scrollController,
    required this.name,
    required this.metadata,
    required this.loading,
    required this.onAlbumTap,
    required this.onHandleDrag,
    required this.onHandleDragEnd,
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
          GestureDetector(
            key: const ValueKey('photo_info_handle'),
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) => onHandleDrag(details.delta.dy),
            onVerticalDragEnd: (details) =>
                onHandleDragEnd(details.primaryVelocity ?? 0),
            child: SizedBox(
              width: double.infinity,
              height: 24,
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            // The sheet stands in for a touch surface, so a mouse drags it
            // too; the app's default scroll behavior leaves mouse drags out.
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
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
          ),
        ],
      ),
    );
  }
}
