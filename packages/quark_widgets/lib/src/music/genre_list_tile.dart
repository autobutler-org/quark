import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';

/// One genre row with its track count.
///
/// Key prefix: `music_genre_<name>` on the row.
///
/// ```dart
/// GenreListTile(
///   name: genre.name,
///   trackCount: genre.trackCount,
///   onTap: openGenre,
/// );
/// ```
class GenreListTile extends StatelessWidget {
  /// Creates a genre row.
  const GenreListTile({
    required this.name,
    required this.trackCount,
    required this.onTap,
    super.key,
  });

  /// The genre's display name and stable API identity.
  final String name;

  /// The number of tracks tagged with [name].
  final int trackCount;

  /// Called with [name] when the row is tapped.
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return ListTile(
      key: ValueKey('music_genre_$name'),
      contentPadding: EdgeInsets.symmetric(horizontal: tokens.spacingMd),
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.sidebar,
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacingSm),
          child: Icon(
            QuarkIcons.audio_file_outlined,
            color: tokens.secondaryForeground,
          ),
        ),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
        style: TextStyle(color: tokens.mutedForeground),
      ),
      onTap: () => onTap(name),
    );
  }
}
