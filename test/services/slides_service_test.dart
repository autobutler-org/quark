import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/slides_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/image_header_size.dart';
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
  late List<int>? downloadBytes;

  /// The Quark: an upload answers with the path it landed at, anything else
  /// with [download].
  http.Client quark() => MockClient.streaming((request, body) async {
    requests.add(request);
    final bytes = await body.toBytes();
    const upload = '/api/v0/files/upload';
    if (!request.url.path.startsWith(upload)) {
      return http.StreamedResponse(
        Stream.value(downloadBytes ?? utf8.encode(download)),
        request.headers.containsKey('range') ? 206 : 200,
      );
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
    downloadBytes = null;
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

  group('pictures on slides (#1158)', () {
    /// The first bytes of a 640×480 PNG.
    final pngHead = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
      0, 0, 2, 128, 0, 0, 1, 224, 8, 6, 0, 0, 0,
    ];

    test('uploads a picture as a stream into the presentation\'s folder, '
        'beside the file, and reads its size from the header', () async {
      final body = [...pngHead, ...List.filled(5000, 7)];
      final progress = <double>[];
      final picture = await withQuark(
        () => SlidesService.uploadImage(
          'talks/Pitch.qslide',
          name: 'dog.png',
          bytes: Stream.fromIterable([
            body.sublist(0, 1000),
            body.sublist(1000),
          ]),
          length: body.length,
          serial: 'usb1',
          onProgress: progress.add,
        ),
      );

      final upload = requests.single;
      expect(upload.url.path, '/api/v0/files/upload/talks');
      expect(upload.url.queryParameters['keepBoth'], 'true');
      expect(upload.url.queryParameters['serial'], 'usb1');
      expect(upload.url.queryParameters.containsKey('overwrite'), isFalse);
      expect(uploads.single, contains('filename="dog.png"'));
      // Where the Quark said it landed, which may be a renamed copy.
      expect(picture.path, 'talks/Pitch.qslide');
      expect(picture.size, (width: 640.0, height: 480.0));
      expect(progress.last, 1.0);
      expect(progress, orderedEquals([...progress]..sort()));
    });

    test(
      'a picture whose header it cannot read uploads with no size',
      () async {
        final picture = await withQuark(
          () => SlidesService.uploadImage(
            'Pitch.qslide',
            name: 'odd.heic',
            bytes: Stream.value(List.filled(64, 1)),
            length: 64,
          ),
        );
        expect(requests.single.url.path, '/api/v0/files/upload');
        expect(picture.size, isNull);
      },
    );

    test(
      'reads the size of a picture on the Quark from its first bytes',
      () async {
        downloadBytes = pngHead;
        final size = await SlidesService.readImageSize(
          'photos/dog.png',
          serial: 'usb1',
        );

        expect(size, (width: 640.0, height: 480.0));
        final request = requests.single;
        expect(request.url.path, '/api/v0/files/download');
        expect(request.url.queryParameters['filePath'], 'photos/dog.png');
        expect(request.url.queryParameters['serial'], 'usb1');
        expect(request.headers['range'], 'bytes=0-${imageHeadLimit - 1}');
      },
    );

    test('a failed read throws for the page to report', () async {
      sharedHttpClientFactory = () =>
          MockClient((request) async => http.Response('', 404));
      resetSharedHttpClient();
      await expectLater(
        SlidesService.readImageSize('photos/gone.png'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
    });
  });

  group('importing PowerPoint (#1171)', () {
    test('knows the PowerPoint files the Quark imports', () {
      expect(SlidesService.isPowerPoint('Talk.pptx'), isTrue);
      expect(SlidesService.isPowerPoint('Talk.PPTM'), isTrue);
      expect(SlidesService.isPowerPoint('Show.ppsx'), isTrue);
      expect(SlidesService.isPowerPoint('Old.ppt'), isFalse);
      expect(SlidesService.isPowerPoint('Talk.qslide'), isFalse);
    });

    test('imports beside the file and reads the warnings', () async {
      download = jsonEncode({
        'path': 'talks/Talk.qslide',
        'mediaDir': 'talks/Talk_media',
        'slides': 4,
        'pictures': 2,
        'warnings': [
          {'slide': 2, 'message': 'Charts are not imported.'},
          {
            'slide': 0,
            'message': 'Animations and transitions are not imported.',
          },
        ],
      });
      final result = await SlidesService.importPowerPoint(
        'talks/Talk.pptx',
        serial: 'usb1',
      );

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v0/files/import/pptx');
      expect(request.url.queryParameters['filePath'], 'talks/Talk.pptx');
      expect(request.url.queryParameters['serial'], 'usb1');
      expect(request.url.queryParameters.containsKey('rootDir'), isFalse);
      expect(result.path, 'talks/Talk.qslide');
      expect(result.slides, 4);
      expect(result.warnings, [
        (slide: 2, message: 'Charts are not imported.'),
        (slide: 0, message: 'Animations and transitions are not imported.'),
      ]);
    });

    test('a refused import throws its status for the page to word', () async {
      sharedHttpClientFactory = () => MockClient(
        (request) async =>
            http.Response('{"error":"pptxutil: not a pptx"}', 400),
      );
      resetSharedHttpClient();
      await expectLater(
        SlidesService.importPowerPoint('talks/Broken.pptx'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
      );
    });

    test('an answer with no path throws', () async {
      download = jsonEncode({'slides': 1, 'warnings': []});
      await expectLater(
        SlidesService.importPowerPoint('talks/Talk.pptx'),
        throwsA(isA<Exception>()),
      );
    });

    test('uploads a PowerPoint file from this device into the member '
        'home, streamed, keeping both on a clash', () async {
      await AppSettings.instance.setUsername('ann');
      final path = await withQuark(
        () => SlidesService.uploadPowerPoint((
          name: 'Talk.pptx',
          length: 3,
          bytes: () => Stream.value([1, 2, 3]),
        )),
      );
      final request = requests.single;
      expect(request.url.path, '/api/v0/files/upload/users/ann');
      expect(request.url.queryParameters['keepBoth'], 'true');
      expect(uploads.single, contains('filename="Talk.pptx"'));
      // The fake Quark answers every upload with the same landed name.
      expect(path, 'users/ann/Pitch.qslide');
    });
  });
}
