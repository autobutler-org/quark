import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

/// How big the tiles of a photo grid are: a slider over the column count,
/// with a step button for larger photos on one side and smaller photos on
/// the other.
///
/// The column count is the caller's: [columns] in, [onColumnsChanged] out,
/// already clamped to [minColumns] and [maxColumns]. It sits at the top of
/// [PhotoLibrarySidebar] on a wide window, and in a "Grid size" sheet on a
/// phone, where the sidebar is not shown.
///
/// Key prefixes: `photo_columns_slider`, `photo_columns_less` (larger
/// photos) and `photo_columns_more` (smaller photos).
///
/// ```dart
/// PhotoColumnsSlider(
///   columns: controller.columns,
///   minColumns: 1,
///   maxColumns: 8,
///   onColumnsChanged: controller.setColumns,
/// );
/// ```
class PhotoColumnsSlider extends StatelessWidget {
  /// Creates the slider at [columns].
  const PhotoColumnsSlider({
    required this.columns,
    required this.minColumns,
    required this.maxColumns,
    required this.onColumnsChanged,
    super.key,
  });

  /// The chosen number of grid columns. Clamped to [minColumns] and
  /// [maxColumns] for display, so a choice made on a wider window survives.
  final int columns;

  /// The fewest columns the slider offers.
  final int minColumns;

  /// The most columns the slider offers.
  final int maxColumns;

  /// Called with the new column count, clamped to [minColumns] and
  /// [maxColumns].
  final ValueChanged<int> onColumnsChanged;

  @override
  Widget build(BuildContext context) {
    final selected = columns.clamp(minColumns, maxColumns);
    final divisions = maxColumns - minColumns;
    return Row(
      children: [
        IconButton(
          key: const ValueKey('photo_columns_less'),
          onPressed: selected > minColumns
              ? () => onColumnsChanged(selected - 1)
              : null,
          icon: const Icon(QuarkIcons.crop_square_outlined),
          tooltip: 'Larger photos',
        ),
        Expanded(
          child: Slider(
            key: const ValueKey('photo_columns_slider'),
            min: minColumns.toDouble(),
            max: maxColumns.toDouble(),
            divisions: divisions > 0 ? divisions : null,
            value: selected.toDouble(),
            onChanged: (value) =>
                onColumnsChanged(value.round().clamp(minColumns, maxColumns)),
          ),
        ),
        IconButton(
          key: const ValueKey('photo_columns_more'),
          onPressed: selected < maxColumns
              ? () => onColumnsChanged(selected + 1)
              : null,
          icon: const Icon(QuarkIcons.grid_view),
          tooltip: 'Smaller photos',
        ),
      ],
    );
  }
}
