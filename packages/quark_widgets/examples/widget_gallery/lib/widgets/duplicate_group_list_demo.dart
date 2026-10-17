import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Holds the marked copies [DuplicateGroupList] refuses to hold, so tapping a
/// copy flips it between Keep and Delete the way a page would. Nothing starts
/// marked; Select suggested marks the identical group's spare copy.
class DuplicateGroupListDemo extends StatefulWidget {
  /// Creates the demo, reporting every callback through [log].
  const DuplicateGroupListDemo({required this.log, super.key});

  /// The gallery's event logger.
  final void Function(String event) log;

  @override
  State<DuplicateGroupListDemo> createState() => _DuplicateGroupListDemoState();
}

class _DuplicateGroupListDemoState extends State<DuplicateGroupListDemo> {
  static const _groups = [
    DuplicateGroupItem(
      id: 'g1',
      isExact: true,
      photos: [
        DuplicatePhotoItem(id: 'a', name: 'beach.jpg', location: 'Camera'),
        DuplicatePhotoItem(
          id: 'b',
          name: 'beach.jpg',
          location: 'Backups/2024',
        ),
      ],
    ),
    DuplicateGroupItem(
      id: 'g2',
      isExact: false,
      photos: [
        DuplicatePhotoItem(id: 'c', name: 'dog.jpg', location: 'Camera'),
        DuplicatePhotoItem(id: 'd', name: 'dog edit.jpg', location: 'Edits'),
      ],
    ),
  ];

  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return DuplicateGroupList(
      groups: _groups,
      selectedIds: _selected,
      thumbnailBuilder: (context, photo) =>
          const ColoredBox(color: Color(0xFF7C8AA0)),
      onToggle: (id) {
        widget.log('DuplicateGroupList.onToggle($id)');
        setState(() {
          if (!_selected.remove(id)) _selected.add(id);
        });
      },
      onDeleteSelected: () => widget.log(
        'DuplicateGroupList.onDeleteSelected(${_selected.join(', ')})',
      ),
      onSelectSuggested: _selected.contains('b')
          ? null
          : () {
              widget.log('DuplicateGroupList.onSelectSuggested');
              setState(() => _selected.add('b'));
            },
      onClearSelection: () {
        widget.log('DuplicateGroupList.onClearSelection');
        setState(_selected.clear);
      },
    );
  }
}
