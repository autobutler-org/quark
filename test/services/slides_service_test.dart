import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/slides_service.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reading and writing `.qslide` files through the files API (#1161).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  late List<http.BaseRequest> requests;
  late List<String> uploads;
  late String download;

  /// The Quark: an upload answers with the path it landed at, anything else
  /// with [download].
  http.Client quark() => MockClient.streaming((request, body) async {
    requests.add(request);
    final bytes = await body.toBytes();
    const upload = '/api/v0/files/upload';
    if (!request.url.path.startsWith(upload)) {
      return http.StreamedResponse(Stream.value(utf8.encode(download)), 200);
    }
    uploads.add(utf8.decode(bytes, allowMalformed: true));
    final dir = request.url.path.substring(upload.length);
    final answer = {
      'paths': ['${dir.replaceFirst(RegExp('^/'), '')}/Pitch.qslide'],
    };
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(answer))),
      200,
    );
  });

  /// A multipart upload sends through the zone's client, not the shared one.
  Future<T> withQuark<T>(Future<T> Function() body) =>
      http.runWithClient(body, quark);

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
    await AppSettings.instance.setSessionToken('a-token');
    requests = [];
    uploads = [];
    download = '';
    sharedHttpClientFactory = quark;
    resetSharedHttpClient();
  });

  tearDown(() async {
    sharedHttpClientFactory = buildLocalTrustHttpClient;
    resetSharedHttpClient();
    AppSettings.instance.isAdmin.value = false;
    await AppSettings.instance.setUsername(null);
    await AppSettings.instance.setSessionToken(null);
  });

  test('a member creates a presentation in their home', () async {
    await AppSettings.instance.setUsername('ann');
    final path = await withQuark(() => SlidesService.create('Pitch'));
    expect(path, 'users/ann/Pitch.qslide');
    expect(requests.single.url.path, '/api/v0/files/upload/users/ann');
    expect(uploads.single, contains('filename="Pitch.qslide"'));
    expect(uploads.single, contains('"schemaVersion"'));
  });

  test('a name that already ends in .qslide is not doubled', () {
    expect(SlidesService.fileNameFor('Pitch.qslide'), 'Pitch.qslide');
    expect(SlidesService.fileNameFor('Pitch'), 'Pitch.qslide');
  });

  test('loads and decodes a presentation', () async {
    final deck = SlidesService.newPresentation('Pitch');
    download = QslideCodec.encode(deck);
    expect(await SlidesService.load('talks/Pitch.qslide'), deck);
  });

  test('an empty file opens as a new presentation named after it', () async {
    final loaded = await SlidesService.load('talks/Empty.qslide');
    expect(loaded.title, 'Empty');
    expect(loaded.slides, hasLength(1));
  });

  test('a file that is not a presentation is refused', () async {
    download = '{"tabs":[]}';
    await expectLater(
      SlidesService.load('talks/x.qslide'),
      throwsA(isA<QslideFormatException>()),
    );
  });

  test('saves over the file in its own folder', () async {
    await withQuark(
      () => SlidesService.save(
        'talks/Pitch.qslide',
        SlidesService.newPresentation('Pitch'),
        serial: 'usb1',
      ),
    );
    final upload = requests.single;
    expect(upload.url.path, '/api/v0/files/upload/talks');
    expect(upload.url.queryParameters['overwrite'], 'true');
    expect(upload.url.queryParameters['serial'], 'usb1');
    expect(uploads.single, contains('filename="Pitch.qslide"'));
  });
}
