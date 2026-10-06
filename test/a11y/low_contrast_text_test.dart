import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #2602: text and meaningful icons take their color from a `QuarkTokens`
/// text color, never a foreground faded below WCAG 1.4.3's 4.5:1.
/// `onSurface` at 40% is about 2.5:1 on white, and `Colors.white38` 3.5:1 on
/// the image viewer's #111111. Fills, scrims, dividers, decorative
/// illustrations and disabled controls are exempt, and are listed below.
void main() {
  /// A foreground role — `onSurface`, `onPrimary`, any `…Foreground` token,
  /// or plain white or black — faded to under 50%, or one of the Material
  /// constants that bakes the same fade in.
  final faded = RegExp(
    r'\b(on[A-Z]\w*|\w*(Foreground|foreground)|Colors\.(white|black))\s*'
    r'\.with(Values\(\s*alpha:\s*|Opacity\(\s*)0?\.[0-4]\d*'
    r'|\bColors\.(white|black)(10|12|24|26|30|38)\b',
  );

  /// The most faded foregrounds each file may hold, and why none is text.
  const allowed = {
    // Decorative empty-state illustrations above a readable message.
    'lib/widgets/docs/docs_body.dart': 1,
    'lib/widgets/sheets/sheets_body.dart': 1,
    'packages/quark_widgets/lib/src/core/empty_state_widget.dart': 1,
    'packages/quark_widgets/lib/src/core/quark_disconnected_state.dart': 1,
    // The home crumb is disabled at the top folder.
    'packages/quark_widgets/lib/src/file_browser/file_breadcrumb_bar.dart': 1,
    // Fills, hover and press overlays, and borders.
    'lib/widgets/document_editor/document_editor_toolbar.dart': 1,
    'lib/widgets/document_editor/highlight_picker_dialog.dart': 1,
    'lib/widgets/slides/slide_image.dart': 1,
    'packages/quark_widgets/lib/src/calendar/calendar_month_grid/'
            'month_day_cell.dart':
        1,
    'packages/quark_widgets/lib/src/settings/quark_theme_color_picker/'
            'theme_color_hue_slider.dart':
        1,
    // The image viewer's drag handle, divider and key-cap fill.
    'lib/widgets/image_viewer/metadata_drawer.dart': 1,
    'lib/widgets/image_viewer/section.dart': 1,
    'lib/widgets/image_viewer/shortcut_row.dart': 1,
    // Video tracks and the trim bar's scrim.
    'lib/widgets/video_viewer/player_controls.dart': 1,
    'lib/widgets/video_viewer/trim_bar.dart': 2,
    // The badge border, and the not-ready dot beside its LIVE label.
    'packages/quark_widgets/lib/src/photos/live_badge.dart': 2,
    // The tile's hairline, selection scrim and the button's backdrop.
    'packages/quark_widgets/lib/src/photos/photo_grid_tile.dart': 4,
    // Still a faded hint, left to the #2607 change that owns this file.
    'packages/quark_widgets/lib/src/albums/album_sidebar.dart': 1,
  };

  test('no text color fades a foreground below 4.5:1', () {
    final offenders = <String>[];
    for (final root in ['lib', 'packages/quark_widgets/lib']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        final matches = faded.allMatches(source).toList();
        if (matches.length <= (allowed[entity.path] ?? 0)) continue;
        for (final match in matches) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length;
          offenders.add('${entity.path}:${line + 1} ${match[0]}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Color text with tokens.mutedForeground, secondaryForeground, '
          'warning, success or error, and image viewer text with white at '
          '70% or more. A fill, scrim or disabled control belongs in '
          '`allowed` with its reason.',
    );
  });
}
