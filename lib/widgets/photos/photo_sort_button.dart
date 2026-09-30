import 'package:flutter/material.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The photo grid's sort control (#2509): one bar button that opens a menu of
/// the six date taken/date added/name x ascending/descending combinations,
/// rather than two separate bar widgets that overflow the actions row on a
/// phone.
///
/// Key prefixes: `photos_sort` on the button, `photos_sort_option_<id>` on
/// each menu row (`taken_desc`, `taken_asc`, `added_desc`, `added_asc`,
/// `name_asc`, `name_desc`).
class PhotoSortButton extends StatelessWidget {
  /// Creates the sort button showing [sortField]/[sortOrder] as the current
  /// choice, calling [onChanged] with the option the user picks.
  const PhotoSortButton({
    required this.sortField,
    required this.sortOrder,
    required this.onChanged,
    super.key,
  });

  /// The field the grid currently orders by.
  final PhotoSortField sortField;

  /// The direction [sortField] currently orders in.
  final PhotoSortOrder sortOrder;

  /// Called with the field and order the user chose from the menu.
  final void Function(PhotoSortField field, PhotoSortOrder order) onChanged;

  static const _options = [
    (
      id: 'taken_desc',
      label: 'Taken, newest first',
      field: PhotoSortField.taken,
      order: PhotoSortOrder.desc,
    ),
    (
      id: 'taken_asc',
      label: 'Taken, oldest first',
      field: PhotoSortField.taken,
      order: PhotoSortOrder.asc,
    ),
    (
      id: 'added_desc',
      label: 'Added, newest first',
      field: PhotoSortField.added,
      order: PhotoSortOrder.desc,
    ),
    (
      id: 'added_asc',
      label: 'Added, oldest first',
      field: PhotoSortField.added,
      order: PhotoSortOrder.asc,
    ),
    (
      id: 'name_asc',
      label: 'Name (A-Z)',
      field: PhotoSortField.name,
      order: PhotoSortOrder.asc,
    ),
    (
      id: 'name_desc',
      label: 'Name (Z-A)',
      field: PhotoSortField.name,
      order: PhotoSortOrder.desc,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return MenuAnchor(
      style: MenuStyle(
        minimumSize: const WidgetStatePropertyAll(Size(200, 0)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusLg),
          ),
        ),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: tokens.spacingSm),
        ),
      ),
      menuChildren: [
        for (final option in _options)
          MenuItemButton(
            key: ValueKey('photos_sort_option_${option.id}'),
            leadingIcon: Icon(_iconFor(option.field), size: 18),
            trailingIcon: option.field == sortField && option.order == sortOrder
                ? Icon(
                    QuarkIcons.check_rounded,
                    size: 16,
                    color: tokens.primary,
                  )
                : null,
            onPressed: () => onChanged(option.field, option.order),
            child: Text(option.label),
          ),
      ],
      builder: (context, controller, _) => QuarkBarIconButton(
        key: const ValueKey('photos_sort'),
        icon: _iconFor(sortField),
        tooltip: 'Sort',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  static IconData _iconFor(PhotoSortField field) => switch (field) {
    PhotoSortField.taken => QuarkIcons.camera_alt_outlined,
    PhotoSortField.added => QuarkIcons.schedule_rounded,
    PhotoSortField.name => QuarkIcons.sort_by_alpha,
  };
}
