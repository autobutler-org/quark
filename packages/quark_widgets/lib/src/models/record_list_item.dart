import 'package:flutter/foundation.dart';

/// One row of a `RecordListCard`: a signed-in session, a connected device,
/// or any other record the user can act on one at a time.
@immutable
class RecordListItem {
  /// Creates a row's data.
  const RecordListItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.hasAction = true,
  });

  /// Identifies the record in keys and in `RecordListCard.onAction`.
  final String id;

  /// What the record is, already named by the caller ("This browser").
  final String title;

  /// The line under [title], such as when the record was last used.
  final String subtitle;

  /// Whether the row gets the card's action button. False leaves it off,
  /// for a record the user may not act on.
  final bool hasAction;
}
