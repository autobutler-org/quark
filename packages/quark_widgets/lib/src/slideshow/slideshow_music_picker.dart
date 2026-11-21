import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_loader.dart';
import '../models/slideshow_music_option.dart';
import '../theme/quark_tokens.dart';

/// The list a slideshow's music button opens: "No music" and then every
/// music album the caller passes, the playing one checked.
///
/// It never loads: the caller passes [options], [isLoading] while it fetches
/// them, and [error] when that failed, and is told which one was picked
/// through [onSelected], with null for "No music".
///
/// Key prefixes: `slideshow_music_none` on "No music", and
/// `slideshow_music_option_<id>` on each choice.
///
/// ```dart
/// SlideshowMusicPicker(
///   options: albums,
///   selectedId: playingAlbumKey,
///   onSelected: chooseMusic,
/// );
/// ```
class SlideshowMusicPicker extends StatelessWidget {
  /// Creates the picker with [selectedId] checked.
  const SlideshowMusicPicker({
    required this.options,
    required this.onSelected,
    this.selectedId,
    this.isLoading = false,
    this.error,
    super.key,
  });

  /// The music to choose from, in the order to list it.
  final List<SlideshowMusicOption> options;

  /// The [SlideshowMusicOption.id] playing now, or null when nothing is.
  final String? selectedId;

  /// Whether the caller is still fetching [options]; shows a loader in their
  /// place.
  final bool isLoading;

  /// Why [options] could not be fetched, written by the caller, or null.
  final String? error;

  /// Called with the picked option's id, or null for "No music".
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;
    return ListView(
      shrinkWrap: true,
      children: [
        ListTile(
          key: const ValueKey('slideshow_music_none'),
          leading: const Icon(QuarkIcons.volume_off),
          title: const Text('No music'),
          trailing: selectedId == null ? const Icon(QuarkIcons.check) : null,
          onTap: () => onSelected(null),
        ),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: QuarkLoader(size: 20)),
          )
        else if (error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(error, style: TextStyle(color: tokens.error)),
          )
        else
          for (final option in options)
            ListTile(
              key: ValueKey('slideshow_music_option_${option.id}'),
              leading: const Icon(QuarkIcons.music_note),
              title: Text(
                option.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: option.subtitle.isEmpty
                  ? null
                  : Text(
                      option.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: option.id == selectedId
                  ? const Icon(QuarkIcons.check)
                  : null,
              onTap: () => onSelected(option.id),
            ),
      ],
    );
  }
}
