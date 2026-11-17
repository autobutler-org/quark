import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/photo_locations.dart';
import 'package:quark/utils/location_clusters.dart';

PhotoLocationPoint _p(
  String path,
  double lat,
  double lon, {
  int year = 2025,
  int month = 1,
}) => PhotoLocationPoint(
  serial: '',
  relPath: path,
  fileName: path,
  latitude: lat,
  longitude: lon,
  takenAt: DateTime.utc(year, month, 15),
  modified: DateTime.utc(2026),
);

/// A household's trips: three shots at a lake house within a few meters, two
/// across Edinburgh, one in Glasgow, two in Sydney, two straddling the
/// antimeridian in Fiji, and one near the North Pole.
final _fixture = [
  _p('lake/1.jpg', 56.80000, -5.10000, year: 2024, month: 6),
  _p('lake/2.jpg', 56.80001, -5.10002, year: 2025, month: 7),
  _p('lake/3.jpg', 56.80003, -5.10001, year: 2026, month: 8),
  _p('edi/castle.jpg', 55.94860, -3.19990),
  _p('edi/leith.jpg', 55.97530, -3.17200),
  _p('gla/1.jpg', 55.86420, -4.25180),
  _p('syd/opera.jpg', -33.85680, 151.21530),
  _p('syd/beach.jpg', -33.89080, 151.27430),
  _p('fiji/east.jpg', -16.50000, 179.99900),
  _p('fiji/west.jpg', -16.50000, -179.99900),
  _p('pole.jpg', 89.90000, 10.00000),
];

List<int> _counts(int zoom) =>
    clusterLocations(_fixture, zoom).map((c) => c.count).toList();

void main() {
  test('clusters merge zoomed out and split zoomed in', () {
    // Zoom 3: all of Scotland is one marker and Sydney another. Fiji's two
    // sit on either side of the antimeridian, at the two edges of the map.
    expect(_counts(3), [6, 2, 1, 1, 1]);
    // Zoom 8: Scotland splits into the lake house and single photos; Sydney's
    // two, 6 km apart, still share a marker.
    expect(_counts(8), [3, 2, 1, 1, 1, 1, 1, 1]);
    // Zoom 12 and 16: only the lake house's three, meters apart, still meet.
    expect(_counts(12), [3, 1, 1, 1, 1, 1, 1, 1, 1]);
    expect(_counts(16), [3, 1, 1, 1, 1, 1, 1, 1, 1]);
  });

  test('every photo lands in exactly one cluster at every zoom', () {
    for (var zoom = 0; zoom <= 20; zoom++) {
      final clusters = clusterLocations(_fixture, zoom);
      final ids = [
        for (final c in clusters)
          for (final p in c.points) p.id,
      ];
      expect(ids.length, _fixture.length, reason: 'zoom $zoom');
      expect(ids.toSet().length, _fixture.length, reason: 'zoom $zoom');
    }
  });

  test('clusters are the same on every run, whatever the input order', () {
    final once = clusterLocations(_fixture, 8);
    final reversed = clusterLocations(_fixture.reversed.toList(), 8);
    expect(
      [for (final c in reversed) '${c.id}:${c.count}:${c.cover.relPath}'],
      [for (final c in once) '${c.id}:${c.count}:${c.cover.relPath}'],
    );
  });

  test('the cover is the newest photo, ties by path', () {
    final lake = clusterLocations(_fixture, 16).first;
    expect(lake.cover.relPath, 'lake/3.jpg');
    final tied = clusterLocations([
      _p('b.jpg', 10, 10),
      _p('a.jpg', 10, 10),
    ], 5).single;
    expect(tied.cover.relPath, 'a.jpg');
  });

  test('the antimeridian never pulls a marker to 0°', () {
    final fiji = clusterLocations(
      _fixture,
      3,
    ).where((c) => c.points.any((p) => p.relPath.startsWith('fiji')));
    expect(fiji, hasLength(2));
    for (final c in fiji) {
      expect(c.longitude.abs(), greaterThan(179));
    }
    // 180° is −180°: the two share a cell and a marker on the antimeridian.
    final wrapped = clusterLocations([
      _p('a.jpg', -16.5, 180),
      _p('b.jpg', -16.5, -179.99),
    ], 3).single;
    expect(wrapped.longitude, lessThan(-179));
  });

  test('poles beyond Web Mercator still land on the map', () {
    final (_, y) = projectToPixels(90, 0, 4);
    expect(y, 0);
    final (_, south) = projectToPixels(-90, 0, 4);
    expect(south, 256.0 * 16);
  });

  test('labels say the count and the date range', () {
    final lake = clusterLocations(_fixture, 16).first;
    expect(
      describeCluster(lake),
      'Cluster of 3 photos, June 2024 to August 2026',
    );
    final single = clusterLocations([_p('x.jpg', 1, 1, month: 3)], 3).single;
    expect(describeCluster(single), '1 photo, March 2025');
  });
}
