import 'package:material_ui/material_ui.dart';
import 'package:quark/models/photo_locations.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The line under the Locations view (#3557): "1,204 of 5,880 photos have a
/// location · 4,676 have none", and while the Quark is still reading photos,
/// how many, so a photo missing from the map is explained.
///
/// Keyed `locations_summary`.
class LocationsSummary extends StatelessWidget {
  /// Creates the line for [locations].
  const LocationsSummary({required this.locations, super.key});

  /// What the Quark reported.
  final PhotoLocations locations;

  /// The sentence the line shows.
  static String describe(PhotoLocations l) {
    final photos = l.total == 1 ? 'photo has' : 'photos have';
    final text =
        '${_count(l.located)} of ${_count(l.total)} $photos a location · '
        '${_count(l.unlocated)} ${l.unlocated == 1 ? 'has' : 'have'} none';
    if (l.pending == 0) return text;
    return '$text · still reading ${_count(l.pending)}, '
        'so more may appear';
  }

  static String _count(int n) => n.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Container(
      key: const ValueKey('locations_summary'),
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacingMd,
        vertical: tokens.spacingSm,
      ),
      color: tokens.card,
      child: Text(
        describe(locations),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: tokens.mutedForeground),
      ),
    );
  }
}
