import 'dart:convert';

import 'package:flutter_map/flutter_map.dart' show DisabledMapCachingProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/widgets/photo_locations/photo_map_tile_layer.dart';

/// Answers every map tile request with a 1×1 PNG from memory, with no
/// cache, for a test of a screen that draws a photo map (#3557). Returns the
/// requests, in order. Call it from `setUp`.
List<http.BaseRequest> useFakeMapTiles() {
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  );
  final requests = <http.BaseRequest>[];
  PhotoMapTileLayer.debugHttpClient = MockClient((request) async {
    requests.add(request);
    return http.Response.bytes(png, 200);
  });
  PhotoMapTileLayer.debugCachingProvider = const DisabledMapCachingProvider();
  addTearDown(() {
    PhotoMapTileLayer.debugHttpClient = null;
    PhotoMapTileLayer.debugCachingProvider = null;
  });
  return requests;
}
