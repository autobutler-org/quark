import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Holds the selection, expansion and sort [AlbumSidebar] refuses to hold, so
/// tapping "All photos" or an album moves the highlight the way a page would.
/// The sort only moves the check: reordering is the caller's job.
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
  AlbumSort _sort = AlbumSort.nameAsc;

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
      onAlbumMenu: (a) => widget.log('AlbumSidebar.onAlbumMenu(${a.name})'),
      sort: _sort,
      onSortChanged: (s) {
        widget.log('AlbumSidebar.onSortChanged(${s.id})');
        setState(() => _sort = s);
      },
    );
  }
}
