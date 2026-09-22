import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The fake album tree the gallery shows, three levels deep so indentation and
/// expansion are both visible.
const AlbumItem _galleryAlbums = AlbumItem(
  id: 1,
  name: 'Trips',
  itemCount: 128,
  children: [
    AlbumItem(
      id: 2,
      name: 'Iceland',
      parentId: 1,
      itemCount: 40,
      children: [
        AlbumItem(id: 4, name: 'Reykjavik', parentId: 2, itemCount: 9),
      ],
    ),
    AlbumItem(id: 3, name: 'Japan', parentId: 1, itemCount: 88),
  ],
);

/// Holds the expansion and selection the tile refuses to hold, which is the
/// point of the example: the gallery is the caller.
class AlbumTreeDemo extends StatefulWidget {
  /// Creates the demo, reporting every callback through [log].
  const AlbumTreeDemo({required this.log, super.key});

  /// The gallery's event logger.
  final void Function(String event) log;

  @override
  State<AlbumTreeDemo> createState() => _AlbumTreeDemoState();
}

class _AlbumTreeDemoState extends State<AlbumTreeDemo> {
  final Set<int> _expanded = {1};
  int? _selected = 2;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: AlbumTreeTile(
        album: _galleryAlbums,
        selectedAlbumId: _selected,
        expandedIds: _expanded,
        onSelected: (album) {
          widget.log('AlbumTreeTile.onSelected(${album.name})');
          setState(() => _selected = album.id);
        },
        onToggleExpanded: (id) {
          widget.log('AlbumTreeTile.onToggleExpanded($id)');
          setState(() {
            if (!_expanded.remove(id)) _expanded.add(id);
          });
        },
        onMenu: (album) => widget.log('AlbumTreeTile.onMenu(${album.name})'),
      ),
    );
  }
}
