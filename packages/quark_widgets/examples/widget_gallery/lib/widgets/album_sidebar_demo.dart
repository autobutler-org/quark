import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Holds the selection and expansion [AlbumSidebar] refuses to hold, so
/// tapping "All photos" or an album moves the highlight the way a page would.
class AlbumSidebarDemo extends StatefulWidget {
  /// Creates the demo over [albums], reporting every callback through [log].
  const AlbumSidebarDemo({
    required this.albums,
    required this.log,
    this.shrinkWrap = false,
    super.key,
  });

  /// The fake albums to list.
  final List<AlbumItem> albums;

  /// The gallery's event logger.
  final void Function(String event) log;

  /// Passed through to [AlbumSidebar.shrinkWrap].
  final bool shrinkWrap;

  @override
  State<AlbumSidebarDemo> createState() => _AlbumSidebarDemoState();
}

class _AlbumSidebarDemoState extends State<AlbumSidebarDemo> {
  final Set<int> _expanded = {3};
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return AlbumSidebar(
      albums: widget.albums,
      expandedIds: _expanded,
      selectedAlbumId: _selected,
      shrinkWrap: widget.shrinkWrap,
      onAllPhotosSelected: () {
        widget.log('AlbumSidebar.onAllPhotosSelected');
        setState(() => _selected = null);
      },
      onAlbumSelected: (a) {
        widget.log('AlbumSidebar.onAlbumSelected(${a.name})');
        setState(() => _selected = a.id);
      },
      onToggleExpanded: (id) {
        widget.log('AlbumSidebar.onToggleExpanded($id)');
        setState(() {
          if (!_expanded.remove(id)) _expanded.add(id);
        });
      },
      onCreateAlbum: () => widget.log('AlbumSidebar.onCreateAlbum'),
      onAlbumLongPress: (a) =>
          widget.log('AlbumSidebar.onAlbumLongPress(${a.name})'),
    );
  }
}
