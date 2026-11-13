// The custom icons are generated from svgs/: `make generate/icons` rebuilds the
// font and its codepoints.

import 'package:material_ui/material_ui.dart' show Icons;
import 'package:flutter/widgets.dart';

// ignore_for_file: constant_identifier_names

/// Every icon the app uses, by semantic name: Quark's own icons from the icon font, and aliases for the Material
/// icons, so the rest of the app never imports Material icons directly.
///
/// Each action has one weight, and the comment on that alias names it.
@staticIconProvider
class QuarkIcons {
  QuarkIcons._();

  static const _fontFamily = 'QuarkIcons';
  static const _fontPackage = 'quark_icons';

  // ── Spreadsheet row operations ──────────────────────────────────────────────

  /// Insert a row above the selected row.
  static const IconData insert_row_above = IconData(
    0xe008,
    fontFamily: _fontFamily,
    fontPackage: _fontPackage,
  );

  /// Insert a row below the selected row.
  static const IconData insert_row_below = IconData(
    0xe009,
    fontFamily: _fontFamily,
    fontPackage: _fontPackage,
  );

  /// Delete the selected row.
  static const IconData delete_row = IconData(
    0xe003,
    fontFamily: _fontFamily,
    fontPackage: _fontPackage,
  );

  /// Duplicate the selected row.
  static const IconData duplicate_row = IconData(
    0xe005,
    fontFamily: _fontFamily,
    fontPackage: _fontPackage,
  );

  /// Clear the contents of the selected row.
  static const IconData clear_row = IconData(
    0xe001,
    fontFamily: _fontFamily,
    fontPackage: _fontPackage,
  );

  // ── Spreadsheet column operations ───────────────────────────────────────────

  /// Insert a column to the left of the selected column.
  static const IconData insert_column_left = IconData(
    0xe006,
    fontFamily: _fontFamily,
    fontPackage: _fontPackage,
  );

  /// Insert a column to the right of the selected column.
  static const IconData insert_column_right = IconData(
    0xe007,
    fontFamily: _fontFamily,
    fontPackage: _fontPackage,
  );

  /// Delete the selected column.
  static const IconData delete_column = IconData(
    0xe002,
    fontFamily: _fontFamily,
    fontPackage: _fontPackage,
  );

  /// Duplicate the selected column.
  static const IconData duplicate_column = IconData(
    0xe004,
    fontFamily: _fontFamily,
    fontPackage: _fontPackage,
  );

  /// Clear the contents of the selected column.
  static const IconData clear_column = IconData(
    0xe000,
    fontFamily: _fontFamily,
    fontPackage: _fontPackage,
  );

  // ── Material aliases ────────────────────────────────────────────────────────────────────────────
  // Re-exports of Icons.* under semantic names.
  // To replace with a custom icon: change the alias here, nowhere else.
  //
  // Toolbar and field actions are rounded. Objects and status marks are
  // outlined. Playback stays the sharp filled glyph. A second const on one
  // stem is a different object, and its comment says which.

  // ── Edit actions ─────────────────────────────────────────────────────────────────────
  static const IconData undo = Icons.undo;
  static const IconData redo = Icons.redo;

  /// Fill cells downward from the current cell.
  static const IconData fill_down =
      Icons.south; // clear directional arrow (not generic back)
  /// Fill cells rightward from the current cell.
  static const IconData fill_right = Icons.east; // clear directional arrow

  /// Cut the selected cells to the clipboard.
  static const IconData content_cut = Icons.content_cut;

  /// Paste the clipboard into the selected cells.
  static const IconData content_paste = Icons.content_paste;

  /// Empty the selected cells, keeping the cells themselves.
  static const IconData clear_range = Icons.backspace_outlined;

  // ── Data operations ───────────────────────────────────────────────────────────────
  static const IconData sort = Icons.sort;
  static const IconData sort_by_alpha = Icons.sort_by_alpha;

  /// Remove duplicate rows — deselect/layers-clear is closest standard icon.
  static const IconData remove_duplicates = Icons.deselect;
  static const IconData find_replace = Icons.find_replace;

  /// Navigate to a specific cell — input/submit arrow reads as 'go to'.
  static const IconData go_to_cell = Icons.input;

  /// Filter a column's rows; the outlined funnel.
  static const IconData filter_column = Icons.filter_alt_outlined;

  /// A column whose filter is hiding rows; the filled funnel.
  static const IconData filter_active = Icons.filter_alt;

  /// Remove every column filter, showing all rows again.
  static const IconData clear_filters = Icons.filter_alt_off_outlined;

  // ── View ─────────────────────────────────────────────────────────────────────────
  /// Freeze header rows and columns. A split pane, not a snowflake.
  static const IconData freeze_panes = Icons.horizontal_split;

  // ── Cell formatting ──────────────────────────────────────────────────────────────
  /// Bold the selected cells' text.
  static const IconData format_bold = Icons.format_bold;

  /// Italicize the selected cells' text.
  static const IconData format_italic = Icons.format_italic;

  /// Color the selected cells' text.
  static const IconData format_text_color = Icons.format_color_text;

  /// Fill the selected cells' background.
  static const IconData format_fill = Icons.format_color_fill;

  /// Align the selected cells' text to the left edge.
  static const IconData format_align_left = Icons.format_align_left;

  /// Center the selected cells' text.
  static const IconData format_align_center = Icons.format_align_center;

  /// Align the selected cells' text to the right edge.
  static const IconData format_align_right = Icons.format_align_right;

  /// Choose how the selected cells display numbers: currency, percent, date.
  /// Drawn as digits, not a currency sign.
  static const IconData format_number = Icons.numbers;

  /// Show one fewer decimal place.
  static const IconData decimal_decrease = Icons.remove;

  /// Show one more decimal place. The sharp plus, not the rounded create icon [add].
  static const IconData decimal_increase = Icons.add;

  /// Remove every format from the selected cells, keeping their values.
  static const IconData format_clear = Icons.format_clear;

  /// The phone menu that holds every formatting action.
  static const IconData format_menu = Icons.text_format;

  // ── Slide editing ────────────────────────────────────────────────────────────────
  /// The pointer tool that selects, moves and resizes slide elements.
  static const IconData select_tool = Icons.near_me_outlined;

  /// Draw a text box on a slide.
  static const IconData text_box = Icons.text_fields;

  /// The menu of shapes to draw on a slide.
  static const IconData shapes = Icons.category_outlined;

  /// Draw a straight line on a slide.
  static const IconData line = Icons.horizontal_rule;

  /// Draw an arrow on a slide.
  static const IconData arrow_line = Icons.arrow_right_alt;

  /// Insert a picture on a slide.
  static const IconData add_image = Icons.add_photo_alternate_outlined;

  /// Underline the selected text.
  static const IconData format_underlined = Icons.format_underlined;

  /// Strike through the selected text.
  static const IconData format_strikethrough = Icons.format_strikethrough;

  /// Justify the selected paragraphs.
  static const IconData format_align_justify = Icons.format_align_justify;

  /// A bulleted list.
  static const IconData format_list_bulleted = Icons.format_list_bulleted;

  /// A numbered list.
  static const IconData format_list_numbered = Icons.format_list_numbered;

  /// The font family of the selected text. A type specimen, not a download.
  static const IconData font_family = Icons.type_specimen;

  /// A shape or line's outline color.
  static const IconData stroke_color = Icons.border_color_outlined;

  /// A shape or line's outline width.
  static const IconData stroke_width = Icons.line_weight;

  /// A shape or line's outline pattern: solid, dashed, dotted.
  static const IconData stroke_dash = Icons.line_style;

  /// A rounded rectangle's corner radius.
  static const IconData corner_radius = Icons.rounded_corner;

  /// An element's opacity.
  static const IconData opacity = Icons.opacity;

  /// Bring the selection forward in the stacking order.
  static const IconData bring_forward = Icons.flip_to_front;

  /// Send the selection backward in the stacking order.
  static const IconData send_backward = Icons.flip_to_back;

  /// The menu of stacking-order moves.
  static const IconData arrange = Icons.layers_outlined;

  /// Show or hide the selection's properties. Outlined. The rounded adjust icon is [tune].
  static const IconData properties = Icons.tune_outlined;

  /// The menu of things to insert on a slide.
  static const IconData insert_menu = Icons.add_box_outlined;

  /// Line up the selected elements' left edges.
  static const IconData align_elements_left = Icons.align_horizontal_left;

  /// Line up the selected elements' vertical center lines.
  static const IconData align_elements_center = Icons.align_horizontal_center;

  /// Line up the selected elements' right edges.
  static const IconData align_elements_right = Icons.align_horizontal_right;

  /// Line up the selected elements' top edges.
  static const IconData align_elements_top = Icons.align_vertical_top;

  /// Line up the selected elements' horizontal center lines.
  static const IconData align_elements_middle = Icons.align_vertical_center;

  /// Line up the selected elements' bottom edges.
  static const IconData align_elements_bottom = Icons.align_vertical_bottom;

  /// Space the selected elements out left to right.
  static const IconData distribute_horizontal = Icons.horizontal_distribute;

  /// Space the selected elements out top to bottom.
  static const IconData distribute_vertical = Icons.vertical_distribute;

  /// Give the selected elements one size.
  static const IconData match_size = Icons.aspect_ratio;

  /// Give the selected elements one width.
  static const IconData match_width = Icons.width_normal;

  /// Give the selected elements one height.
  static const IconData match_height = Icons.height;

  /// Group the selected elements. Overlapping shapes, not a join.
  static const IconData group_elements = Icons.group_work;

  /// Break a group into its elements. The group glyph with a slash.
  static const IconData ungroup_elements = Icons.group_off;

  /// Copy the selection in place.
  static const IconData duplicate = Icons.control_point_duplicate;

  /// A slide's background.
  static const IconData slide_background = Icons.wallpaper;

  /// A presentation's theme: its colors and fonts.
  static const IconData slide_theme = Icons.palette_outlined;

  /// A slide's layout: where its placeholders sit.
  static const IconData slide_layout = Icons.view_quilt_outlined;

  /// A slide's transition: how the show moves on to it.
  static const IconData slide_transition = Icons.auto_awesome_motion_outlined;

  /// Put a slide's placeholders back where its layout has them. The same glyph as [restart].
  static const IconData reset_layout = Icons.restart_alt;

  /// The list of keyboard shortcuts.
  static const IconData keyboard_shortcuts = Icons.keyboard_outlined;

  /// Insert a table on a slide, and a slide table's controls.
  static const IconData insert_table = Icons.table_chart_outlined;

  /// Merge the selected table cells into one.
  static const IconData merge_cells = Icons.call_merge;

  /// Split a merged table cell back into its cells.
  static const IconData unmerge_cells = Icons.call_split;

  /// A table's header row: its first row filled with the accent.
  static const IconData table_header_row = Icons.web_asset;

  /// A table's banded rows: every other row shaded.
  static const IconData table_banded_rows = Icons.table_rows_outlined;

  /// Lines along every edge of the selected cells.
  static const IconData border_all = Icons.border_all;

  /// Lines around the outside of the selected cells.
  static const IconData border_outside = Icons.border_outer;

  /// A line along the bottom of the selected cells.
  static const IconData border_bottom = Icons.border_bottom;

  /// No lines on the selected cells.
  static const IconData border_none = Icons.border_clear;

  /// Insert a chart on a slide, and a slide chart's controls.
  static const IconData insert_chart = Icons.insert_chart_outlined;

  /// A chat poll, on its card and the composer's entry for one.
  static const IconData poll = Icons.poll_outlined;

  /// What kind of chart a slide chart is: bars, lines, a pie.
  static const IconData chart_kind = Icons.bar_chart;

  /// A chart's numbers, edited in a grid.
  static const IconData chart_data = Icons.grid_on;

  /// A chart's title.
  static const IconData chart_title = Icons.title;

  /// A chart's legend: which color is which series.
  static const IconData chart_legend = Icons.list_alt;

  /// The value written on each bar, point or slice of a chart.
  static const IconData chart_data_labels = Icons.pin_outlined;

  /// The lines across a chart's plot at each value tick. Horizontal rules, not [wireframe].
  static const IconData chart_gridlines = Icons.border_horizontal;

  /// The model viewer's wireframe toggle. A 4 by 4 lattice, not [chart_gridlines].
  static const IconData wireframe = Icons.grid_4x4;

  /// The colors of a chart's series.
  static const IconData chart_colors = Icons.palette_outlined;

  /// Read a grid of numbers from the clipboard into a chart.
  static const IconData paste_data = Icons.content_paste_go;

  // ── Import / Export ────────────────────────────────────────────────────────────────
  /// Export data as a CSV file.
  static const IconData export_csv = Icons.file_download;

  /// Import data from a CSV file.
  static const IconData import_csv = Icons.file_upload;

  /// Import a file from another app's format, such as a PowerPoint file.
  static const IconData import_file = Icons.file_open_outlined;

  // ── Navigation & chrome ──────────────────────────────────────────────────────────
  /// Back. Rounded.
  static const IconData arrow_back = Icons.arrow_back_rounded;

  /// The previous item. Rounded, with [arrow_back].
  static const IconData chevron_left = Icons.chevron_left_rounded;

  /// The next item, and the disclosure at the end of a row. Rounded.
  static const IconData chevron_right = Icons.chevron_right_rounded;

  /// Collapse a section. Rounded, the pair of [expand_more].
  static const IconData expand_less = Icons.expand_less_rounded;

  /// Expand a section, including the caret on a split chip. Rounded.
  static const IconData expand_more = Icons.expand_more_rounded;

  /// The previous match in a find bar, and the scroll-up hint. Rounded.
  static const IconData keyboard_arrow_up_rounded =
      Icons.keyboard_arrow_up_rounded;

  /// Dismiss, and the button that clears a search field. Rounded.
  static const IconData close = Icons.close_rounded;

  /// Breadcrumb overflow. Rounded, with the chevrons.
  static const IconData more_horiz_rounded = Icons.more_horiz_rounded;

  /// An item's menu. Sharp. This menu has no second weight.
  static const IconData more_vert = Icons.more_vert;

  /// Home. Rounded.
  static const IconData home = Icons.home_rounded;

  /// Search. Rounded.
  static const IconData search = Icons.search_rounded;

  /// The device switcher on the drawer header. Rounded, with the chevrons.
  static const IconData unfold_more = Icons.unfold_more_rounded;

  /// The caret on a share-row menu. A dropdown triangle, not [expand_more].
  static const IconData arrow_drop_down = Icons.arrow_drop_down;

  static const IconData fullscreen = Icons.fullscreen;
  static const IconData fullscreen_exit = Icons.fullscreen_exit;
  static const IconData zoom_in = Icons.zoom_in;
  static const IconData zoom_out = Icons.zoom_out;
  static const IconData fit_screen = Icons.fit_screen;
  static const IconData refresh = Icons.refresh;

  // ── Indicators & status ──────────────────────────────────────────────────────────
  /// A chosen menu row, and the mark inside a circle the widget already paints. Rounded.
  static const IconData check = Icons.check_rounded;

  /// The select control, a selected file, and a success mark. Outlined.
  static const IconData check_circle_outline = Icons.check_circle_outline;

  /// A status dot. Filled. An empty selection circle is [circle_outlined].
  static const IconData circle = Icons.circle;

  /// An empty selection circle. Outlined, the pair of [check_circle_outline].
  static const IconData circle_outlined = Icons.circle_outlined;
  static const IconData error_outline = Icons.error_outline;
  static const IconData help_outline = Icons.help_outline;

  /// Detail is showing. Filled. The idle control is [info_outline].
  static const IconData info = Icons.info;

  /// Detail is hidden. Outlined, the pair of [info].
  static const IconData info_outline = Icons.info_outline;

  /// A warning. Sharp amber. The rounded warning is not used.
  static const IconData warning_amber = Icons.warning_amber;
  static const IconData remove_circle_outline = Icons.remove_circle_outline;
  static const IconData pending_actions_outlined =
      Icons.pending_actions_outlined;
  static const IconData schedule_rounded = Icons.schedule_rounded;
  static const IconData update = Icons.update;
  static const IconData access_time_outlined = Icons.access_time_outlined;
  static const IconData monitor_heart_outlined = Icons.monitor_heart_outlined;

  // ── Files & folders ──────────────────────────────────────────────────────────────
  /// An open folder. Outlined, the same weight as [folder].
  static const IconData folder_open = Icons.folder_open_outlined;
  static const IconData backup_outlined = Icons.backup_outlined;
  static const IconData verified_outlined = Icons.verified_outlined;
  static const IconData label_outline = Icons.label_outline;

  /// A folder. Outlined.
  static const IconData folder = Icons.folder_outlined;
  static const IconData folder_copy_outlined = Icons.folder_copy_outlined;
  static const IconData folder_off_outlined = Icons.folder_off_outlined;

  /// Make a new folder. Outlined, the same weight as [folder].
  static const IconData create_new_folder_outlined =
      Icons.create_new_folder_outlined;
  static const IconData insert_drive_file_outlined =
      Icons.insert_drive_file_outlined;
  static const IconData description_outlined = Icons.description_outlined;
  static const IconData archive_outlined = Icons.archive_outlined;

  /// Save. Outlined.
  static const IconData save = Icons.save_outlined;

  /// Copy. Filled.
  static const IconData content_copy = Icons.content_copy;

  // ── Media file types ─────────────────────────────────────────────────────────────
  static const IconData image_outlined = Icons.image_outlined;

  /// A picture that failed to load. Outlined.
  static const IconData broken_image = Icons.broken_image_outlined;

  /// The photo library. Outlined.
  static const IconData photo_library = Icons.photo_library_outlined;
  static const IconData photo_album_outlined = Icons.photo_album_outlined;
  static const IconData photo_size_select_large_outlined =
      Icons.photo_size_select_large_outlined;
  static const IconData picture_as_pdf_outlined = Icons.picture_as_pdf_outlined;
  static const IconData menu_book_outlined = Icons.menu_book_outlined;

  /// A Quark slide deck. Filled, so it is not [slideshow_outlined].
  static const IconData slideshow = Icons.slideshow;

  /// A presentation that is not a Quark deck, and the Slides section. Outlined.
  static const IconData slideshow_outlined = Icons.slideshow_outlined;
  static const IconData video_file_outlined = Icons.video_file_outlined;
  static const IconData audio_file_outlined = Icons.audio_file_outlined;

  /// A Quark spreadsheet. Filled, so it is not [table_chart_outlined].
  static const IconData table_chart = Icons.table_chart;

  /// A spreadsheet that is not a Quark sheet, and the Sheets section. Outlined.
  static const IconData table_chart_outlined = Icons.table_chart_outlined;

  /// A Quark document. Filled.
  static const IconData edit_document = Icons.edit_document;
  static const IconData edit_note = Icons.edit_note;

  // ── Actions & editing ────────────────────────────────────────────────────────────
  /// Create. Rounded.
  static const IconData add = Icons.add_rounded;

  static const IconData remove = Icons.remove;
  static const IconData edit_outlined = Icons.edit_outlined;
  static const IconData casino = Icons.casino;
  static const IconData delete_outline = Icons.delete_outline;
  static const IconData delete_forever_outlined = Icons.delete_forever_outlined;
  static const IconData restore = Icons.restore;

  /// Restart Quark, or reset an installation. The same glyph as [reset_layout].
  static const IconData restart = Icons.restart_alt;
  static const IconData drive_folder_upload_outlined =
      Icons.drive_folder_upload_outlined;

  /// A file moving into a folder: Move on the Files selection bar.
  static const IconData drive_file_move_outlined =
      Icons.drive_file_move_outlined;

  /// A link. Outlined.
  static const IconData link = Icons.link_outlined;

  static const IconData link_off = Icons.link_off;
  static const IconData eject_outlined = Icons.eject_outlined;
  static const IconData open_in_new = Icons.open_in_new;

  /// Download. Outlined.
  static const IconData download_outlined = Icons.download_outlined;
  static const IconData share_outlined = Icons.share_outlined;

  /// Upload. Rounded.
  static const IconData upload_rounded = Icons.upload_rounded;
  static const IconData arrow_downward_rounded = Icons.arrow_downward_rounded;
  static const IconData arrow_upward_rounded = Icons.arrow_upward_rounded;
  static const IconData rotate_90_degrees_cw_outlined =
      Icons.rotate_90_degrees_cw_outlined;
  static const IconData crop_square_outlined = Icons.crop_square_outlined;
  static const IconData straighten_outlined = Icons.straighten_outlined;

  /// Adjust. Rounded.
  static const IconData tune = Icons.tune_rounded;
  static const IconData print_outlined = Icons.print_outlined;
  static const IconData palette_outlined = Icons.palette_outlined;

  // ── Media playback ───────────────────────────────────────────────────────────────
  /// Play. Sharp. Playback does not use the rounded play glyph.
  static const IconData play_arrow = Icons.play_arrow;
  static const IconData pause = Icons.pause;
  static const IconData forward_10 = Icons.forward_10;
  static const IconData replay_10 = Icons.replay_10;
  static const IconData volume_up = Icons.volume_up;
  static const IconData volume_off = Icons.volume_off;

  /// A music note. Rounded.
  static const IconData music_note = Icons.music_note_rounded;

  // ── Devices & storage ────────────────────────────────────────────────────────────
  static const IconData devices = Icons.devices;
  static const IconData smartphone = Icons.smartphone;
  static const IconData computer_outlined = Icons.computer_outlined;

  /// A storage volume or device. Rounded.
  static const IconData storage = Icons.storage_rounded;

  /// Memory. The chip, not the storage volume.
  static const IconData memory = Icons.memory;

  /// CPU. A board, not the memory chip.
  static const IconData cpu = Icons.developer_board;
  static const IconData disc_full = Icons.disc_full;
  static const IconData usb_outlined = Icons.usb_outlined;
  static const IconData radio_button_checked = Icons.radio_button_checked;
  static const IconData radio_button_unchecked = Icons.radio_button_unchecked;
  static const IconData device_hub_outlined = Icons.device_hub_outlined;
  static const IconData thermostat = Icons.thermostat;

  // ── Cloud & sync ─────────────────────────────────────────────────────────────────
  static const IconData cloud = Icons.cloud;
  static const IconData cloud_done_outlined = Icons.cloud_done_outlined;
  static const IconData cloud_off_outlined = Icons.cloud_off_outlined;
  static const IconData cloud_sync_outlined = Icons.cloud_sync_outlined;

  // ── Security & accounts ──────────────────────────────────────────────────────────
  /// A key. Outlined.
  static const IconData key = Icons.key_outlined;
  static const IconData key_off_outlined = Icons.key_off_outlined;
  static const IconData lock_open = Icons.lock_open;
  static const IconData lock_outline = Icons.lock_outline;
  static const IconData shield_outlined = Icons.shield_outlined;
  static const IconData logout = Icons.logout;
  static const IconData person_outline = Icons.person_outline;
  static const IconData group_outlined = Icons.group_outlined;

  /// Show a secret. Outlined.
  static const IconData visibility = Icons.visibility_outlined;

  /// Hide a secret. Outlined, the pair of [visibility].
  static const IconData visibility_off = Icons.visibility_off_outlined;

  // ── Views & layout ───────────────────────────────────────────────────────────────
  /// The grid. Rounded, the pair of [view_list_rounded].
  static const IconData grid_view = Icons.grid_view_rounded;

  /// The list. Rounded, the pair of [grid_view].
  static const IconData view_list_rounded = Icons.view_list_rounded;
  static const IconData view_column_outlined = Icons.view_column_outlined;
  static const IconData lens_outlined = Icons.lens_outlined;

  // ── Calendar ─────────────────────────────────────────────────────────────────────
  static const IconData calendar_month_outlined = Icons.calendar_month_outlined;
  static const IconData today_outlined = Icons.today_outlined;
  static const IconData view_day_outlined = Icons.view_day_outlined;
  static const IconData view_week_outlined = Icons.view_week_outlined;
  static const IconData view_agenda_outlined = Icons.view_agenda_outlined;
  static const IconData event_repeat_outlined = Icons.event_repeat_outlined;
  static const IconData notifications_outlined = Icons.notifications_outlined;
  static const IconData notes_rounded = Icons.notes_rounded;

  // ── Misc ─────────────────────────────────────────────────────────────────────────
  /// A favorite that is on. Rounded.
  static const IconData star = Icons.star_rounded;

  /// A favorite that is off. Rounded, the pair of [star].
  static const IconData star_border = Icons.star_outline_rounded;
  static const IconData settings_outlined = Icons.settings_outlined;
  static const IconData keyboard_outlined = Icons.keyboard_outlined;
  static const IconData camera_alt_outlined = Icons.camera_alt_outlined;
  static const IconData calendar_today_outlined = Icons.calendar_today_outlined;
  static const IconData location_on_outlined = Icons.location_on_outlined;

  /// Follow the system theme. Rounded, with [light_mode] and [dark_mode].
  static const IconData brightness_auto_rounded = Icons.brightness_auto_rounded;

  /// The light theme. Rounded.
  static const IconData light_mode = Icons.light_mode_rounded;

  /// The dark theme. Rounded.
  static const IconData dark_mode = Icons.dark_mode_rounded;
  static const IconData bug_report_outlined = Icons.bug_report_outlined;

  /// Repair an installation. Outlined.
  static const IconData build_outlined = Icons.build_outlined;

  /// Terms. Outlined.
  static const IconData gavel_outlined = Icons.gavel_outlined;

  /// The API explorer.
  static const IconData api = Icons.api;

  // ── Chat ─────────────────────────────────────────────────────────────────────────
  static const IconData tag = Icons.tag;
  static const IconData attach_file = Icons.attach_file;
  static const IconData send_rounded = Icons.send_rounded;
  static const IconData forum_outlined = Icons.forum_outlined;

  /// Open the sidebar. Sharp.
  static const IconData menu = Icons.menu;

  /// The sidebar is open. Sharp, the pair of [menu].
  static const IconData menu_open = Icons.menu_open;
  static const IconData person_add_outlined = Icons.person_add_outlined;
  static const IconData add_reaction_outlined = Icons.add_reaction_outlined;
}
