import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The genre the Songs tab is filtered to, with a button that clears it.
///
/// Key prefixes: `music_genre_filter` on the chip and
/// `music_genre_filter_clear` on its clear button.
class MusicGenreFilter extends StatelessWidget {
  /// Shows the filter on [genre].
  const MusicGenreFilter({
    required this.genre,
    required this.onClear,
    super.key,
  });

  /// The genre the songs are filtered to.
  final String genre;

  /// Called when the filter is cleared.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacingMd,
        tokens.spacingSm,
        tokens.spacingMd,
        0,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: InputChip(
          key: const ValueKey('music_genre_filter'),
          label: Text('Genre: $genre'),
          deleteIcon: const Icon(
            QuarkIcons.close,
            key: ValueKey('music_genre_filter_clear'),
          ),
          deleteButtonTooltipMessage: 'Show every genre',
          onDeleted: onClear,
        ),
      ),
    );
  }
}
