import 'package:material_ui/material_ui.dart';

import '../../models/photo_index_failure_item.dart';
import '../../theme/quark_tokens.dart';

/// One file a `PhotoIndexStatusPanel` lists as unreadable: its name, then
/// where it is and why it could not be read.
///
/// Key prefix: `photo_index_failure_<id>` on the row.
///
/// ```dart
/// PhotoIndexFailureRow(failure: failure);
/// ```
class PhotoIndexFailureRow extends StatelessWidget {
  /// Creates the row for [failure].
  const PhotoIndexFailureRow({required this.failure, super.key});

  /// The file that could not be read.
  final PhotoIndexFailureItem failure;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return Padding(
      key: ValueKey('photo_index_failure_${failure.id}'),
      padding: EdgeInsets.symmetric(vertical: tokens.spacingXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            failure.name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.foreground,
            ),
          ),
          Text(
            '${failure.location} · ${failure.reason}',
            style: TextStyle(fontSize: 12, color: tokens.mutedForeground),
          ),
        ],
      ),
    );
  }
}
