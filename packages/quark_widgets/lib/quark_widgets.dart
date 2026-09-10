/// Quark's reusable widgets and design tokens.
///
/// Everything the app renders that is not a page, a controller, or a service
/// lives here. The package depends on Flutter and `quark_icons` and nothing
/// else — no services, no router, no HTTP — so every widget is testable in
/// isolation and can be shown in `examples/widget_gallery`.
///
/// See the "Widget package rules" section of `AGENTS.md` for the contract.
library;

export 'src/albums/album_tree_tile.dart';
export 'src/core/copy_button.dart';
export 'src/core/empty_state_widget.dart';
export 'src/core/password_strength_bar.dart';
export 'src/core/quark_disconnected_state.dart';
export 'src/core/quark_file_icon.dart';
export 'src/core/quark_storage_bar.dart';
export 'src/file_browser/file_breadcrumb_bar.dart';
export 'src/file_browser/file_browser_header.dart';
export 'src/file_browser/file_selection_bar.dart';
export 'src/file_browser/new_file_dialog.dart';
export 'src/layout/quark_app_bar.dart';
export 'src/layout/quark_brand_button.dart';
export 'src/layout/quark_checkerboard.dart';
export 'src/layout/quark_drawer.dart';
export 'src/layout/quark_page_scaffold.dart';
export 'src/layout/quark_section.dart';
export 'src/layout/quark_split_view.dart';
export 'src/layout/quark_toolbar.dart';
export 'src/layout/refresh_icon_button.dart';
export 'src/layout/theme_toggle_button.dart';
export 'src/models/album_item.dart';
export 'src/photos/live_badge.dart';
export 'src/photos/photo_selection_bar.dart';
export 'src/theme/quark_colors.dart';
export 'src/theme/quark_theme.dart';
export 'src/theme/quark_tokens.dart';
