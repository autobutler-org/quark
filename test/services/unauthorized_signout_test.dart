import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secure_storage.dart';

/// #3724: a 401 signs the user out on every authenticated path, not only the
/// ones that went through the mixin's verbs, and every request goes out on the
/// shared client.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final stored = <String, String>{};
  final requests = <http.BaseRequest>[];

  setUpAll(() {
    mockSecureStorage(stored);
  });

  setUp(() async {
    stored.clear();
    requests.clear();
    SharedPreferences.setMockInitialValues({
      'hosts': jsonEncode([
        {'name': 'One', 'hostAddress': 'http://one.local'},
      ]),
      'activeHostIndex': 0,
    });
    await AppSettings.instance.load();
    await AppSettings.instance.setSessionToken('session-token');
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient.streaming((request, body) async {
      requests.add(request);
      await body.drain<void>();
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"error":"not authenticated"}')),
        401,
      );
    });
  });

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  final calls = <String, Future<Object?> Function()>{
    'StorageService.mountDevice': () => StorageService.mountDevice('ABC123'),
    'RemoteAccessService.getStatus': RemoteAccessService.getStatus,
    'FilesService.createFolder': () => FilesService.createFolder('', 'New'),
    'FilesService.uploadFilesFromFormData': () =>
        FilesService.uploadFilesFromFormData('', [
          http.MultipartFile.fromString('files', 'hello', filename: 'a.txt'),
        ]),
    'FilesService.putThumbnail': () => FilesService.putThumbnail(
      path: 'a.jpg',
      thumbnail: Uint8List.fromList([1, 2, 3]),
    ),
  };

  for (final MapEntry(key: name, value: call) in calls.entries) {
    test('a 401 from $name signs the user out', () async {
      await expectLater(call(), throwsA(isA<UnauthorizedException>()));
      expect(AppSettings.instance.bearerToken, isNull);
      expect(requests, hasLength(1), reason: 'sent on the shared client');
    });
  }
}
