// Custom icon font for Quark.
//
// Sections:
//   1. Custom icons — generated from SVGs in svgs/. Run `make generate/icons`
//      to rebuild the font + update codepoints.
//   2. Material aliases — re-exports of Icons.* under semantic names so the
//      rest of the app never imports package:flutter/material.dart for icons
//      directly. To swap a Material icon for a custom one in the future,
//      change the alias here and nowhere else.
//
// Usage:
//   import 'package:quark_icons/quark_icons.dart';
//   Icon(QuarkIcons.insert_row_above)
//   Icon(QuarkIcons.undo)

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

// ignore_for_file: constant_identifier_names

/// Every icon the app uses, by semantic name: Quark's own icons from the icon font, and aliases for the Material
/// icons, so the rest of the app never imports Material icons directly.
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

  // ── Edit actions ─────────────────────────────────────────────────────────────────────
  static const IconData undo = Icons.undo;
  static const IconData redo = Icons.redo;

  /// Fill cells downward from the current cell.
  static const IconData fill_down =
      Icons.south; // clear directional arrow (not generic back)
  /// Fill cells rightward from the current cell.
  static const IconData fill_right = Icons.east; // clear directional arrow

  // ── Data operations ───────────────────────────────────────────────────────────────
  static const IconData sort = Icons.sort;

  /// Remove duplicate rows — deselect/layers-clear is closest standard icon.
  static const IconData remove_duplicates = Icons.deselect;
  static const IconData find_replace = Icons.find_replace;

  /// Navigate to a specific cell — input/submit arrow reads as 'go to'.
  static const IconData go_to_cell = Icons.input;

  // ── Import / Export ────────────────────────────────────────────────────────────────
  /// Export data as a CSV file.
  static const IconData export_csv = Icons.file_download;

  /// Import data from a CSV file.
  static const IconData import_csv = Icons.file_upload;

  // ── Navigation & chrome ──────────────────────────────────────────────────────────
  static const IconData arrow_back = Icons.arrow_back;
  static const IconData arrow_back_rounded = Icons.arrow_back_rounded;
  static const IconData chevron_left = Icons.chevron_left;
  static const IconData chevron_left_rounded = Icons.chevron_left_rounded;
  static const IconData chevron_right = Icons.chevron_right;
  static const IconData chevron_right_rounded = Icons.chevron_right_rounded;
  static const IconData expand_less = Icons.expand_less;
  static const IconData expand_more = Icons.expand_more;
  static const IconData expand_more_rounded = Icons.expand_more_rounded;
  static const IconData keyboard_arrow_up_rounded =
      Icons.keyboard_arrow_up_rounded;
  static const IconData close = Icons.close;
  static const IconData close_rounded = Icons.close_rounded;
  static const IconData clear_rounded = Icons.clear_rounded;
  static const IconData more_horiz = Icons.more_horiz;
  static const IconData more_horiz_rounded = Icons.more_horiz_rounded;
  static const IconData more_vert = Icons.more_vert;
  static const IconData home_filled = Icons.home_filled;
  static const IconData home_rounded = Icons.home_rounded;
  static const IconData search = Icons.search;
  static const IconData search_rounded = Icons.search_rounded;
  static const IconData fullscreen = Icons.fullscreen;
  static const IconData fullscreen_exit = Icons.fullscreen_exit;
  static const IconData refresh = Icons.refresh;
  static const IconData refresh_rounded = Icons.refresh_rounded;

  // ── Indicators & status ──────────────────────────────────────────────────────────
  static const IconData check = Icons.check;
  static const IconData check_rounded = Icons.check_rounded;
  static const IconData check_circle_outline = Icons.check_circle_outline;
  static const IconData check_circle_outline_rounded =
      Icons.check_circle_outline_rounded;
  static const IconData check_circle_rounded = Icons.check_circle_rounded;
  static const IconData circle = Icons.circle;
  static const IconData circle_outlined = Icons.circle_outlined;
  static const IconData error_outline = Icons.error_outline;
  static const IconData help_outline = Icons.help_outline;
  static const IconData info = Icons.info;
  static const IconData info_outline = Icons.info_outline;
  static const IconData warning_amber = Icons.warning_amber;
  static const IconData remove_circle_outline = Icons.remove_circle_outline;
  static const IconData pending_actions_outlined =
      Icons.pending_actions_outlined;
  static const IconData schedule_rounded = Icons.schedule_rounded;
  static const IconData update = Icons.update;
  static const IconData access_time_outlined = Icons.access_time_outlined;
  static const IconData monitor_heart_outlined = Icons.monitor_heart_outlined;

  // ── Files & folders ──────────────────────────────────────────────────────────────
  static const IconData folder_open = Icons.folder_open;
  static const IconData folder_open_outlined = Icons.folder_open_outlined;
  static const IconData folder_open_rounded = Icons.folder_open_rounded;
  static const IconData backup_outlined = Icons.backup_outlined;
  static const IconData verified_outlined = Icons.verified_outlined;
  static const IconData label_outline = Icons.label_outline;
  static const IconData folder_outlined = Icons.folder_outlined;
  static const IconData folder_rounded = Icons.folder_rounded;
  static const IconData folder_copy_outlined = Icons.folder_copy_outlined;
  static const IconData folder_off_outlined = Icons.folder_off_outlined;
  static const IconData create_new_folder_outlined =
      Icons.create_new_folder_outlined;
  static const IconData insert_drive_file_outlined =
      Icons.insert_drive_file_outlined;
  static const IconData description_outlined = Icons.description_outlined;
  static const IconData archive_outlined = Icons.archive_outlined;
  static const IconData save = Icons.save;
  static const IconData save_outlined = Icons.save_outlined;
  static const IconData copy_outlined = Icons.copy_outlined;
  static const IconData content_copy = Icons.content_copy;

  // ── Media file types ─────────────────────────────────────────────────────────────
  static const IconData image_outlined = Icons.image_outlined;
  static const IconData broken_image = Icons.broken_image;
  static const IconData broken_image_outlined = Icons.broken_image_outlined;
  static const IconData photo_library = Icons.photo_library;
  static const IconData photo_library_outlined = Icons.photo_library_outlined;
  static const IconData photo_album_outlined = Icons.photo_album_outlined;
  static const IconData photo_size_select_large_outlined =
      Icons.photo_size_select_large_outlined;
  static const IconData picture_as_pdf_outlined = Icons.picture_as_pdf_outlined;
  static const IconData slideshow_outlined = Icons.slideshow_outlined;
  static const IconData video_file_outlined = Icons.video_file_outlined;
  static const IconData audio_file_outlined = Icons.audio_file_outlined;
  static const IconData table_chart = Icons.table_chart;
  static const IconData table_chart_outlined = Icons.table_chart_outlined;
  static const IconData edit_document = Icons.edit_document;
  static const IconData edit_note = Icons.edit_note;

  // ── Actions & editing ────────────────────────────────────────────────────────────
  static const IconData add = Icons.add;
  static const IconData add_rounded = Icons.add_rounded;
  static const IconData add_link = Icons.add_link;
  static const IconData edit = Icons.edit;
  static const IconData edit_outlined = Icons.edit_outlined;
  static const IconData copy = Icons.copy;
  static const IconData casino = Icons.casino;
  static const IconData delete_outline = Icons.delete_outline;
  static const IconData delete_forever_outlined = Icons.delete_forever_outlined;
  static const IconData restore = Icons.restore;
  static const IconData drive_folder_upload_outlined =
      Icons.drive_folder_upload_outlined;
  static const IconData link_outlined = Icons.link_outlined;
  static const IconData link_rounded = Icons.link_rounded;
  static const IconData link_off = Icons.link_off;
  static const IconData open_in_new = Icons.open_in_new;
  static const IconData download_outlined = Icons.download_outlined;
  static const IconData upload_rounded = Icons.upload_rounded;
  static const IconData arrow_downward_rounded = Icons.arrow_downward_rounded;
  static const IconData arrow_upward_rounded = Icons.arrow_upward_rounded;
  static const IconData rotate_90_degrees_cw_outlined =
      Icons.rotate_90_degrees_cw_outlined;
  static const IconData crop_square_outlined = Icons.crop_square_outlined;
  static const IconData straighten_outlined = Icons.straighten_outlined;
  static const IconData tune_outlined = Icons.tune_outlined;
  static const IconData tune_rounded = Icons.tune_rounded;
  static const IconData print_outlined = Icons.print_outlined;
  static const IconData palette_outlined = Icons.palette_outlined;

  // ── Media playback ───────────────────────────────────────────────────────────────
  static const IconData play_arrow = Icons.play_arrow;
  static const IconData play_arrow_rounded = Icons.play_arrow_rounded;
  static const IconData pause = Icons.pause;
  static const IconData forward_10 = Icons.forward_10;
  static const IconData replay_10 = Icons.replay_10;
  static const IconData volume_up = Icons.volume_up;
  static const IconData volume_off = Icons.volume_off;

  // ── Devices & storage ────────────────────────────────────────────────────────────
  static const IconData devices = Icons.devices;
  static const IconData smartphone = Icons.smartphone;
  static const IconData computer_outlined = Icons.computer_outlined;
  static const IconData storage = Icons.storage;
  static const IconData storage_outlined = Icons.storage_outlined;
  static const IconData storage_rounded = Icons.storage_rounded;
  static const IconData memory = Icons.memory;
  static const IconData disc_full = Icons.disc_full;
  static const IconData usb_outlined = Icons.usb_outlined;
  static const IconData usb_rounded = Icons.usb_rounded;
  static const IconData usb_off = Icons.usb_off;
  static const IconData usb_off_rounded = Icons.usb_off_rounded;
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
  static const IconData key_outlined = Icons.key_outlined;
  static const IconData key_rounded = Icons.key_rounded;
  static const IconData key_off_outlined = Icons.key_off_outlined;
  static const IconData vpn_key_outlined = Icons.vpn_key_outlined;
  static const IconData lock_open = Icons.lock_open;
  static const IconData lock_outline = Icons.lock_outline;
  static const IconData shield_outlined = Icons.shield_outlined;
  static const IconData logout = Icons.logout;
  static const IconData person_outline = Icons.person_outline;
  static const IconData group_outlined = Icons.group_outlined;
  static const IconData visibility = Icons.visibility;
  static const IconData visibility_off = Icons.visibility_off;
  static const IconData visibility_outlined = Icons.visibility_outlined;
  static const IconData visibility_off_outlined = Icons.visibility_off_outlined;

  // ── Views & layout ───────────────────────────────────────────────────────────────
  static const IconData grid_view_outlined = Icons.grid_view_outlined;
  static const IconData grid_view_rounded = Icons.grid_view_rounded;
  static const IconData view_list_rounded = Icons.view_list_rounded;
  static const IconData lens_outlined = Icons.lens_outlined;

  // ── Misc ─────────────────────────────────────────────────────────────────────────
  static const IconData star = Icons.star;
  static const IconData star_border = Icons.star_border;
  static const IconData star_rounded = Icons.star_rounded;
  static const IconData star_outline_rounded = Icons.star_outline_rounded;
  static const IconData settings_outlined = Icons.settings_outlined;
  static const IconData keyboard_outlined = Icons.keyboard_outlined;
  static const IconData camera_alt_outlined = Icons.camera_alt_outlined;
  static const IconData calendar_today_outlined = Icons.calendar_today_outlined;
  static const IconData location_on_outlined = Icons.location_on_outlined;
  static const IconData brightness_auto_rounded = Icons.brightness_auto_rounded;
  static const IconData light_mode_outlined = Icons.light_mode_outlined;
  static const IconData dark_mode_outlined = Icons.dark_mode_outlined;
  static const IconData light_mode_rounded = Icons.light_mode_rounded;
  static const IconData dark_mode_rounded = Icons.dark_mode_rounded;
  static const IconData bug_report_outlined = Icons.bug_report_outlined;
}
