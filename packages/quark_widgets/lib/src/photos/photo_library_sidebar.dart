import 'package:material_ui/material_ui.dart';

import '../layout/quark_split_view.dart';
import '../theme/quark_tokens.dart';

/// The sidebar of a photo library: an optional tile-size control, an
/// optional category picker, and an album list underneath.
///
/// Built to sit in a [QuarkSplitView] pane, and it asks that widget which
/// shape to take rather than being told, so nothing upstream has to know the
/// breakpoint. Wide, it fills the pane and gives [albums] the remaining
/// height. Narrow, as in a bottom sheet on a phone, it has unbounded height,
/// so it shrink-wraps and never wraps [albums] in an [Expanded] (#1599).
/// [albums] has to shrink-wrap there too.
///
/// [sizeControl] is usually a `PhotoColumnsSlider`. A phone leaves it out:
/// there the sidebar is a picker sheet, and the grid size has a sheet of its
/// own.
///
/// Key prefixes: none of its own; its parts carry theirs.
///
/// ```dart
/// PhotoLibrarySidebar(
///   sizeControl: PhotoColumnsSlider(...),
///   categories: PhotoCategoryList(...),
///   albums: AlbumSidebar(...),
/// );
/// ```
class PhotoLibrarySidebar extends StatelessWidget {
  /// Creates the sidebar.
  const PhotoLibrarySidebar({
    required this.albums,
    this.sizeControl,
    this.categories,
    super.key,
  });

  /// The album list, below everything else.
  final Widget albums;

  /// The tile-size control at the top, or null for none.
  final Widget? sizeControl;

  /// The category picker under the size control, or null for none.
  final Widget? categories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QuarkTokens.of(context);
    final compact = QuarkSplitView.isCollapsed(context);
    final sizeControl = this.sizeControl;
    final categories = this.categories;

    // Material, not a colored Container: the list tiles inside paint their
    // background and ink on the nearest Material ancestor, and a plain
    // ColoredBox in between would hide both.
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: EdgeInsets.all(tokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            ?sizeControl,
            if (categories != null) ...[
              if (sizeControl != null) SizedBox(height: tokens.spacingSm),
              categories,
            ],
            if (sizeControl != null || categories != null)
              SizedBox(height: tokens.spacingMd),
            if (compact) albums else Expanded(child: albums),
          ],
        ),
      ),
    );
  }
}
