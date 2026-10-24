import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/playback_position_service.dart';
import 'package:quark/utils/error_text.dart';

import '../support/fake_quark_http.dart';

/// The video resume API client (#2985): the routes it calls, what it sends,
/// and what it reads back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  useFakeQuark();

  test('get asks for one file on one device and reads its state', () async {
    answer(200, {
      'positionMs': 4000,
      'durationMs': 10000,
      'watched': false,
      'updatedAt': '2026-10-10T09:30:00Z',
    });

    final state = await PlaybackPositionService.get(
      'Movies/clip.mp4',
      serial: 'USB1',
    );

    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/v0/playback');
    expect(requests.single.url.queryParameters, {
      'relPath': 'Movies/clip.mp4',
      'deviceSerial': 'USB1',
    });
    expect(state.position, const Duration(seconds: 4));
    expect(state.duration, const Duration(seconds: 10));
    expect(state.watched, isFalse);
  });

  test('save puts the position and adopts the state as stored', () async {
    answer(200, {'positionMs': 0, 'durationMs': 10000, 'watched': true});

    final state = await PlaybackPositionService.save(
      'Movies/clip.mp4',
      position: const Duration(milliseconds: 9800),
      duration: const Duration(seconds: 10),
    );

    expect(requests.single.method, 'PUT');
    expect(requests.single.url.path, '/api/v0/playback');
    expect(jsonDecode(requests.single.body), {
      'relPath': 'Movies/clip.mp4',
      'deviceSerial': '',
      'positionMs': 9800,
      'durationMs': 10000,
    });
    expect(state.watched, isTrue);
    expect(state.position, Duration.zero);
  });

  test('setWatched puts the flag to the watched route', () async {
    answer(200, {'positionMs': 0, 'durationMs': 0, 'watched': false});

    final state = await PlaybackPositionService.setWatched(
      'Movies/clip.mp4',
      serial: 'USB1',
      watched: false,
    );

    expect(requests.single.method, 'PUT');
    expect(requests.single.url.path, '/api/v0/playback/watched');
    expect(jsonDecode(requests.single.body), {
      'relPath': 'Movies/clip.mp4',
      'deviceSerial': 'USB1',
      'watched': false,
    });
    expect(state.watched, isFalse);
  });

  for (final (name, call) in <(String, Future<Object?> Function())>[
    ('get', () => PlaybackPositionService.get('a.mp4')),
    (
      'save',
      () => PlaybackPositionService.save(
        'a.mp4',
        position: Duration.zero,
        duration: Duration.zero,
      ),
    ),
    (
      'setWatched',
      () => PlaybackPositionService.setWatched('a.mp4', watched: true),
    ),
  ]) {
    test('$name throws the status of a refusal', () async {
      answer(404, {'error': 'no such file'});

      await expectLater(
        call(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });
  }
}
