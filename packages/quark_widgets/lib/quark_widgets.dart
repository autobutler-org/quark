/// Quark's reusable widgets and design tokens.
///
/// Everything the app renders that is not a page, a controller, or a service
/// lives here. The package depends on Flutter and `quark_icons` and nothing
/// else — no services, no router, no HTTP — so every widget is testable in
/// isolation and can be shown in `examples/widget_gallery`.
///
/// See the "Widget package rules" section of `AGENTS.md` for the contract.
library;

export 'src/albums/add_to_album_sheet.dart';
export 'src/albums/album_picker_sheet.dart';
export 'src/albums/album_sidebar.dart';
export 'src/albums/album_tree_tile.dart';
export 'src/core/confirm_delete_dialog.dart';
export 'src/core/copy_button.dart';
export 'src/core/empty_state_widget.dart';
export 'src/core/password_strength_bar.dart';
export 'src/core/quark_disconnected_state.dart';
export 'src/core/quark_file_icon.dart';
export 'src/core/quark_loader.dart';
export 'src/core/quark_name_dialog.dart';
export 'src/core/quark_storage_bar.dart';
export 'src/core/scroll_up_hint.dart';
export 'src/file_browser/file_breadcrumb_bar.dart';
export 'src/file_browser/file_browser_header.dart';
export 'src/file_browser/file_selection_bar.dart';
export 'src/file_browser/file_shortcut_bar.dart';
export 'src/file_browser/new_file_dialog.dart';
export 'src/file_browser/shared_roots_sheet.dart';
export 'src/file_browser/upload_conflict_dialog.dart';
export 'src/jobs/job_list.dart';
export 'src/jobs/jobs_badge.dart';
export 'src/layout/quark_app_bar.dart';
export 'src/layout/quark_app_bar_bottom.dart';
export 'src/layout/quark_app_bar_trailing.dart';
export 'src/layout/quark_bar_chip.dart';
export 'src/layout/quark_bar_icon_button.dart';
export 'src/layout/quark_bar_segmented_toggle.dart';
export 'src/layout/quark_brand_button.dart';
export 'src/layout/quark_checkerboard.dart';
export 'src/layout/quark_drawer.dart';
export 'src/layout/quark_page_scaffold.dart';
export 'src/layout/quark_section.dart';
export 'src/layout/quark_split_view.dart';
export 'src/layout/quark_tab_view.dart';
export 'src/layout/quark_toolbar.dart';
export 'src/layout/refresh_icon_button.dart';
export 'src/layout/theme_toggle_button.dart';
export 'src/models/access_level.dart';
export 'src/models/album_item.dart';
export 'src/models/create_user_input.dart';
export 'src/models/file_shortcut.dart';
export 'src/models/grant_item.dart';
export 'src/models/group_item.dart';
export 'src/models/host_item.dart';
export 'src/models/job_item.dart';
export 'src/models/photo_category_entry.dart';
export 'src/models/photo_item.dart';
export 'src/models/principal_item.dart';
export 'src/models/shared_root_item.dart';
export 'src/models/ssh_key_item.dart';
export 'src/models/transcode_format_option.dart';
export 'src/models/transcode_quality.dart';
export 'src/models/upload_target.dart';
export 'src/models/user_account_item.dart';
export 'src/photos/live_badge.dart';
export 'src/photos/photo_category_list.dart';
export 'src/photos/photo_grid.dart';
export 'src/photos/photo_grid_tile.dart';
export 'src/photos/photo_library_sidebar.dart';
export 'src/photos/photo_selection_bar.dart';
export 'src/settings/ssh_access_panel.dart';
export 'src/sheets/sheet_tab_strip.dart';
export 'src/sharing/share_sheet.dart';
export 'src/storage/upload_target_picker.dart';
export 'src/theme/quark_colors.dart';
export 'src/theme/quark_theme.dart';
export 'src/theme/quark_tokens.dart';
export 'src/users/access_requests_tile.dart';
export 'src/users/create_user_dialog.dart';
export 'src/users/group_list.dart';
export 'src/users/group_members_sheet.dart';
export 'src/users/pending_request_list.dart';
export 'src/users/principal_picker.dart';
export 'src/users/user_list.dart';
export 'src/video/transcode_dialog.dart';
