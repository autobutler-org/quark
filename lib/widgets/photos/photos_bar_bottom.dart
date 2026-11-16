import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Photos page's second bar row: what the grid shows on the left, then
/// the page's [pinnedActions] (Upload and Search) and the page's tools on the
/// right (#2576). The pinned ones stay in the row at every width, which is
/// what leaves the top bar room for the page name on a phone.
///
/// Duplicates used to be a copy icon in the top row whose only name was a
/// hover tooltip, which a touch screen never shows. Here it is a chip reading
/// "Duplicates", and below `QuarkAppBarBottom.collapseBreakpoint` a menu
/// labeled "Tools" holding it, so the word is on screen at every width.
///
/// On a phone the library sidebar is not on screen (#4149), so the page
/// passes [onPickLibrary] and [onGridSize]. The title becomes a chip that
/// opens the library picker, and "Grid size" joins the tools. Without them
/// the title is plain text, as on a wide window, where the sidebar carries
/// both.
///
/// A phone uploads from a + button rather than the Upload chip (#4150), so
/// the page passes [onUploadToDevice] there and "Upload to a device" joins
/// the tools: the chip's second half, which picks the drive.
///
/// Key prefixes: `photos_library_picker` on the title chip,
/// `photos_duplicates` and `photos_grid_size` on the tool chips,
/// `app_bar_bottom_menu` on the menu, and `photos_menu_duplicates` and
/// `photos_menu_grid_size` and `photos_menu_upload_to_device` on its items.
class PhotosBarBottom extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the row reading [title].
  const PhotosBarBottom({
    required this.title,
    this.onDuplicates,
    this.onPickLibrary,
    this.onGridSize,
    this.onUploadToDevice,
    this.pinnedActions = const [],
    super.key,
  });

  /// What the grid shows, such as "Library" or an album's name.
  final String title;

  /// Opens the duplicates review. Null leaves Duplicates out, for a library
  /// the Quark does not hold, such as Demo mode's.
  final VoidCallback? onDuplicates;

  /// Opens the library picker: All photos, the categories and the albums.
  /// Null renders [title] as plain text.
  final VoidCallback? onPickLibrary;

  /// Opens the grid-size control. Null leaves "Grid size" out.
  final VoidCallback? onGridSize;

  /// Uploads after asking which device to write to. Null leaves "Upload to
  /// a device" out.
  final VoidCallback? onUploadToDevice;

  /// Bar buttons shown beside the tools, or beside their menu, at every
  /// width.
  final List<Widget> pinnedActions;

  static const _duplicatesTooltip = 'Find photos saved more than once';

  @override
  Size get preferredSize => const Size.fromHeight(QuarkAppBarBottom.height);

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onDuplicates = this.onDuplicates;
    final onPickLibrary = this.onPickLibrary;
    final onGridSize = this.onGridSize;
    final onUploadToDevice = this.onUploadToDevice;
    return QuarkAppBarBottom(
      lead: Align(
        alignment: Alignment.centerLeft,
        child: onPickLibrary == null
            ? Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: tokens.foreground),
              )
            : QuarkBarChip(
                key: const ValueKey('photos_library_picker'),
                icon: QuarkIcons.photo_library,
                label: title,
                tooltip: 'Choose an album',
                keepLabel: true,
                onPressed: onPickLibrary,
              ),
      ),
      pinnedActions: pinnedActions,
      actions: [
        if (onGridSize != null)
          QuarkBarIconButton(
            key: const ValueKey('photos_grid_size'),
            icon: QuarkIcons.grid_view,
            tooltip: 'Grid size',
            onPressed: onGridSize,
          ),
        if (onDuplicates != null)
          QuarkBarChip(
            key: const ValueKey('photos_duplicates'),
            icon: QuarkIcons.content_copy,
            label: 'Duplicates',
            tooltip: _duplicatesTooltip,
            keepLabel: true,
            onPressed: onDuplicates,
          ),
      ],
      menuLabel: 'Tools',
      menuChildren: [
        if (onUploadToDevice != null)
          MenuItemButton(
            key: const ValueKey('photos_menu_upload_to_device'),
            onPressed: onUploadToDevice,
            child: quarkMenuLabel(
              leading: const Icon(QuarkIcons.upload_rounded),
              label: const Text('Upload to a device'),
            ),
          ),
        if (onGridSize != null)
          MenuItemButton(
            key: const ValueKey('photos_menu_grid_size'),
            onPressed: onGridSize,
            child: quarkMenuLabel(
              leading: const Icon(QuarkIcons.grid_view),
              label: const Text('Grid size'),
            ),
          ),
        if (onDuplicates != null)
          MenuItemButton(
            key: const ValueKey('photos_menu_duplicates'),
            onPressed: onDuplicates,
            child: quarkMenuLabel(
              leading: const Icon(QuarkIcons.content_copy),
              label: const Text('Duplicates'),
            ),
          ),
      ],
    );
  }
}
