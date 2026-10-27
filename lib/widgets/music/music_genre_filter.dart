import 'package:flutter/material.dart';

/// The chip above Songs naming the genre it is narrowed to, whose delete
/// button shows every song again.
///
/// Key: `music_genre_filter` on the chip.
class MusicGenreFilter extends StatelessWidget {
  /// Creates the chip for [genre], '' for the untagged tracks.
  const MusicGenreFilter({
    required this.genre,
    required this.onClear,
    super.key,
  });

  /// The genre Songs shows.
  final String genre;

  /// Shows every song again.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: InputChip(
          key: const ValueKey('music_genre_filter'),
          label: Text(genre.isEmpty ? 'Unknown genre' : genre),
          deleteButtonTooltipMessage: 'Show every song',
          onDeleted: onClear,
        ),
      ),
    );
  }
}
