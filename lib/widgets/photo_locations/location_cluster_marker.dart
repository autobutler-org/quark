import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/location_clusters.dart';
import 'package:quark/utils/photo_map_config.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One marker on the photo map (#3557): [thumbnail], the cluster's cover
/// photo, with a count badge when it holds more than one. A button a
/// keyboard can reach and a screen reader names with [describeCluster]
/// ("Cluster of 42 photos, June 2024 to August 2026"); at
/// [PhotoMapConfig.markerSize] it stays above the 44 px touch target.
///
/// Keyed `location_cluster_<cluster id>`.
class LocationClusterMarker extends StatelessWidget {
  /// Creates the marker.
  const LocationClusterMarker({
    required this.cluster,
    required this.thumbnail,
    required this.onTap,
    this.onDoubleTap,
    this.selected = false,
    super.key,
  });

  /// The photos the marker stands for.
  final LocationCluster cluster;

  /// The cover photo's picture.
  final Widget thumbnail;

  /// Opens the cluster's photos.
  final VoidCallback onTap;

  /// Zooms the map into the cluster.
  final VoidCallback? onDoubleTap;

  /// Whether the cluster's photos are the ones showing.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    const size = PhotoMapConfig.markerSize;
    final radius = BorderRadius.circular(tokens.radiusMd);
    return Semantics(
      button: true,
      selected: selected,
      label: describeCluster(cluster),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('location_cluster_${cluster.id}'),
        borderRadius: radius,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: selected ? tokens.primary : tokens.card,
                      width: selected ? 3 : 2,
                    ),
                    boxShadow: const [
                      BoxShadow(blurRadius: 4, color: Color(0x55000000)),
                    ],
                  ),
                  child: ClipRRect(borderRadius: radius, child: thumbnail),
                ),
              ),
              if (cluster.count > 1)
                Positioned(
                  top: -tokens.spacingSm,
                  right: -tokens.spacingSm,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: tokens.spacingXs + 2,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 22),
                    decoration: BoxDecoration(
                      color: tokens.primary,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: tokens.card, width: 1.5),
                    ),
                    child: Text(
                      '${cluster.count}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tokens.primaryForeground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
