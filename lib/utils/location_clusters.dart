import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:quark/models/photo_locations.dart';
import 'package:quark/utils/photo_map_config.dart';

/// Photos whose markers would overlap at one zoom level, drawn as one marker
/// (#3557).
@immutable
class LocationCluster {
  /// Creates a cluster of [points], which must already be newest first.
  const LocationCluster({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.points,
  });

  /// Stable for a zoom level and grid cell: `<zoom>/<column>/<row>`.
  final String id;

  /// Where the marker sits: the mean position of [points].
  final double latitude;
  final double longitude;

  /// The photos in the cluster, newest first, ties by drive then path.
  final List<PhotoLocationPoint> points;

  /// How many photos the cluster holds.
  int get count => points.length;

  /// The photo whose thumbnail the marker shows: the most recent, ties
  /// broken by path. No scoring of any kind picks it.
  PhotoLocationPoint get cover => points.first;

  /// The oldest and newest dates among [points].
  DateTime get earliest => points.last.date;
  DateTime get latest => points.first.date;
}

/// Groups [points] into the clusters a map at [zoom] draws (#3557).
///
/// Pure geometry, the same on every run: each point is projected to Web
/// Mercator pixels at [zoom] and falls in one square cell of
/// [PhotoMapConfig.clusterCellPixels]; a cell's points are one cluster.
/// Zooming in shrinks the cells against the world, so clusters split until
/// each photo stands alone at street level. Latitudes beyond Web Mercator's
/// ±85.05° are drawn at its edge, and longitude 180° is the same meridian as
/// −180°, so the antimeridian never splits a cell. Every point lands in
/// exactly one cluster, so the counts always add up to [points.length].
///
/// Clusters come largest first, ties by [LocationCluster.id].
List<LocationCluster> clusterLocations(
  List<PhotoLocationPoint> points,
  int zoom,
) {
  final worldPixels = 256.0 * math.pow(2, zoom);
  const cell = PhotoMapConfig.clusterCellPixels;
  final cellsAcross = (worldPixels / cell).ceil();
  final cells = <String, List<PhotoLocationPoint>>{};
  for (final point in points) {
    final (x, y) = projectToPixels(point.latitude, point.longitude, zoom);
    final column = (x / cell).floor().clamp(0, cellsAcross - 1);
    final row = (y / cell).floor().clamp(0, cellsAcross - 1);
    cells.putIfAbsent('$zoom/$column/$row', () => []).add(point);
  }
  final clusters = [
    for (final MapEntry(key: id, value: members) in cells.entries)
      _cluster(id, members),
  ];
  clusters.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.id.compareTo(b.id);
  });
  return clusters;
}

/// The Web Mercator pixel position of [latitude], [longitude] on a world
/// 256 × 2^[zoom] pixels across. Longitude 180° wraps to 0, the same pixel
/// as −180°.
(double, double) projectToPixels(double latitude, double longitude, int zoom) {
  final world = 256.0 * math.pow(2, zoom);
  final x = ((longitude + 180) / 360 * world) % world;
  final lat = latitude.clamp(-85.05112878, 85.05112878) * math.pi / 180;
  final sinLat = math.sin(lat);
  final y =
      (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * world;
  return (x, y.clamp(0.0, world).toDouble());
}

/// Newest first, ties by drive then path: the order a cluster lists its
/// photos in and picks its cover by.
int compareNewestFirst(PhotoLocationPoint a, PhotoLocationPoint b) {
  final byDate = b.date.compareTo(a.date);
  if (byDate != 0) return byDate;
  final bySerial = a.serial.compareTo(b.serial);
  return bySerial != 0 ? bySerial : a.relPath.compareTo(b.relPath);
}

LocationCluster _cluster(String id, List<PhotoLocationPoint> members) {
  members.sort(compareNewestFirst);
  var lat = 0.0;
  var lon = 0.0;
  for (final p in members) {
    lat += p.latitude;
    // 180° and −180° share a cell; averaging them as one keeps the marker
    // on the antimeridian rather than at 0°.
    lon += p.longitude == 180 ? -180 : p.longitude;
  }
  return LocationCluster(
    id: id,
    latitude: lat / members.length,
    longitude: lon / members.length,
    points: List.unmodifiable(members),
  );
}

/// What a screen reader says for [cluster], and what the list shows: "1
/// photo, June 2024" or "Cluster of 42 photos, June 2024 to August 2026".
String describeCluster(LocationCluster cluster) {
  final range = describeDateRange(cluster.earliest, cluster.latest);
  if (cluster.count == 1) return '1 photo, $range';
  return 'Cluster of ${cluster.count} photos, $range';
}

/// "June 2024" when [from] and [to] share a month, otherwise
/// "June 2024 to August 2026".
String describeDateRange(DateTime from, DateTime to) {
  String month(DateTime d) => '${_months[d.month - 1]} ${d.year}';
  final a = month(from.toLocal());
  final b = month(to.toLocal());
  return a == b ? a : '$a to $b';
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
