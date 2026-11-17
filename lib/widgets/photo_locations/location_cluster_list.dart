import 'package:material_ui/material_ui.dart';
import 'package:quark/models/photo_locations.dart';
import 'package:quark/utils/location_clusters.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Locations view's list (#3557), the map's accessible alternative: one
/// row per cluster with its cover thumbnail, count and date range, and its
/// position rounded to two decimals for display. Every row is a button a
/// keyboard and a screen reader reach in order, and choosing one opens the
/// same photos its marker does.
///
/// Keyed `location_row_<cluster id>`.
class LocationClusterList extends StatelessWidget {
  /// Creates the list.
  const LocationClusterList({
    required this.clusters,
    required this.thumbnailBuilder,
    required this.onSelected,
    this.selectedId,
    super.key,
  });

  /// The clusters, largest first.
  final List<LocationCluster> clusters;

  /// A cover photo's picture.
  final Widget Function(BuildContext context, PhotoLocationPoint point)
  thumbnailBuilder;

  /// Called with the cluster the user chose.
  final ValueChanged<LocationCluster> onSelected;

  /// The cluster whose photos are showing.
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: tokens.spacingSm),
      itemCount: clusters.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final cluster = clusters[i];
        final position =
            '${cluster.latitude.toStringAsFixed(2)}, '
            '${cluster.longitude.toStringAsFixed(2)}';
        return ListTile(
          key: ValueKey('location_row_${cluster.id}'),
          selected: cluster.id == selectedId,
          minTileHeight: 64,
          leading: SizedBox.square(
            dimension: 48,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              child: ExcludeSemantics(
                child: thumbnailBuilder(context, cluster.cover),
              ),
            ),
          ),
          title: Text(describeCluster(cluster)),
          subtitle: Text(position),
          onTap: () => onSelected(cluster),
        );
      },
    );
  }
}
