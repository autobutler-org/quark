import 'package:flutter/material.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The photo grid's sort control (#2509): one bar button that opens a menu of
/// the four Date/Name x ascending/descending combinations, rather than two
/// separate bar widgets that overflow the actions row on a phone.
///
/// Key prefixes: `photos_sort` on the button, `photos_sort_option_<id>` on
/// each menu row (`added_desc`, `added_asc`, `name_asc`, `name_desc`).
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
      id: 'added_desc',
      label: 'Newest first',
      field: PhotoSortField.added,
      order: PhotoSortOrder.desc,
    ),
    (
      id: 'added_asc',
      label: 'Oldest first',
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
            leadingIcon: Icon(
              option.field == PhotoSortField.name
                  ? QuarkIcons.sort_by_alpha
                  : QuarkIcons.schedule_rounded,
              size: 18,
            ),
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
        icon: sortField == PhotoSortField.name
            ? QuarkIcons.sort_by_alpha
            : QuarkIcons.schedule_rounded,
        tooltip: 'Sort',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
