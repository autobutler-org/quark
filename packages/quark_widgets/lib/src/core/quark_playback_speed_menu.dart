import 'package:material_ui/material_ui.dart';

/// The one playback speed picker: the current speed as text, opening a menu
/// of the six speeds from 0.5x to 2x.
///
/// The video and audio players both show it. The menu is a popup menu, so it
/// opens on the shared menu panel (#4099). The caller owns the speed and
/// decides what a pick does.
///
/// Key prefixes: `playback_speed_<speed>` on each menu row, such as
/// `playback_speed_1.5`. The caller's `key` sits on the button.
///
/// ```dart
/// QuarkPlaybackSpeedMenu(
///   speed: value.playbackSpeed,
///   onSelected: controller.setPlaybackSpeed,
/// );
/// ```
class QuarkPlaybackSpeedMenu extends StatelessWidget {
  /// Creates a speed picker showing [speed].
  const QuarkPlaybackSpeedMenu({
    required this.speed,
    required this.onSelected,
    this.textStyle,
    super.key,
  });

  /// The speeds the menu offers, slowest first.
  static const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  /// The speed playing now, shown on the button and checked in the menu.
  final double speed;

  /// Called with the picked speed.
  final ValueChanged<double> onSelected;

  /// The button label's style, such as white text over a video. Null uses
  /// the theme's `bodyMedium`.
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'Playback speed',
      initialValue: speed,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final s in speeds)
          PopupMenuItem(
            key: ValueKey('playback_speed_$s'),
            value: s,
            child: Text('${s}x'),
          ),
      ],
      // A 48dp floor keeps the text button a full touch target.
      child: Container(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          '${speed.toStringAsFixed(2)}x',
          style: textStyle ?? Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
