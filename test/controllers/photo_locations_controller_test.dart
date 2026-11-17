import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/photo_locations_controller.dart';
import 'package:quark/models/photo_locations.dart';
import 'package:quark/widgets/photo_locations/locations_summary.dart';

PhotoLocationPoint _p(
  String path,
  double lat,
  double lon, {
  String serial = '',
}) => PhotoLocationPoint(
  serial: serial,
  relPath: path,
  fileName: path,
  latitude: lat,
  longitude: lon,
  takenAt: DateTime.utc(2025),
  modified: DateTime.utc(2026),
);

void main() {
  final points = [
    _p('trip/a.jpg', 48.8566, 2.3522),
    _p('trip/b.jpg', 48.8567, 2.3523, serial: 'USB-1'),
    _p('home/c.jpg', -33.85, 151.21),
  ];

  PhotoLocationsController controller({List<(int, String, String)>? added}) =>
      PhotoLocationsController(
        fetchLocations: () async => PhotoLocations(
          points: points,
          total: 10,
          located: 3,
          unlocated: 7,
          pending: 0,
        ),
        addPhotoToAlbum:
            (albumId, {required deviceSerial, required relPath}) async {
              added?.add((albumId, deviceSerial, relPath));
              return true;
            },
        thumbnailUrl: (path, {serial, size}) => Uri.parse('memory:$path'),
      );

  test('a cluster opens exactly its own photos', () async {
    final c = controller();
    await c.load();
    c.setZoom(12);
    final paris = c.clusters.firstWhere((cl) => cl.count == 2);
    c.select(paris);
    expect(c.selectedPhotos.map((p) => p.id).toSet(), {
      ':trip/a.jpg',
      'USB-1:trip/b.jpg',
    });
  });

  test('adding to an album makes the same pointer the library does, '
      'nothing copied', () async {
    final added = <(int, String, String)>[];
    final c = controller(added: added);
    await c.load();
    c.setZoom(12);
    c.select(c.clusters.firstWhere((cl) => cl.count == 2));
    c.toggleSelection(0);
    c.toggleSelection(1);
    final outcome = await c.addSelectedToAlbum(7);
    expect(outcome.added, 2);
    expect(added.toSet(), {(7, '', 'trip/a.jpg'), (7, 'USB-1', 'trip/b.jpg')});
    expect(c.selectedIds, isEmpty);
  });

  test('the open cluster stays open as the map zooms', () async {
    final c = controller();
    await c.load();
    c.setZoom(12);
    final paris = c.clusters.firstWhere((cl) => cl.count == 2);
    c.select(paris);
    c.setZoom(16);
    expect(c.selected, same(paris));
  });

  test('the summary counts photos with and without a location', () {
    expect(
      LocationsSummary.describe(
        const PhotoLocations(
          points: [],
          total: 5880,
          located: 1204,
          unlocated: 4676,
          pending: 0,
        ),
      ),
      '1,204 of 5,880 photos have a location · 4,676 have none',
    );
  });
}
