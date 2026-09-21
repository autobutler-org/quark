import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';

/// A delete or move the Quark refuses has to reach the user as a reason, not
/// a bare status (#2178).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void answer(int status, Map<String, Object?> body) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () =>
        MockClient((_) async => http.Response(jsonEncode(body), status));
  }

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  const homeRefusal = "a home folder can't be deleted or moved";

  final calls = <String, Future<void> Function()>{
    'deleteFile': () => FilesService.deleteFile('users', 'bob'),
    'deleteFiles': () => FilesService.deleteFiles(['bob'], rootDir: 'users'),
    'moveFile': () => FilesService.moveFile('users/bob', 'users/robert'),
  };

  for (final MapEntry(key: name, value: call) in calls.entries) {
    test("$name carries a 403's own sentence", () async {
      answer(403, {'error': homeRefusal});

      final error = await call().then<Object?>((_) => null, onError: (e) => e);

      expect(
        Errors.message(error, 'move the item'),
        "A home folder can't be deleted or moved.",
      );
    });

    test('$name keeps a 500 body out of the message', () async {
      answer(500, {'error': 'rename /srv/quark/users/bob: permission denied'});

      final error = await call().then<Object?>((_) => null, onError: (e) => e);

      expect(error, isA<ApiException>());
      expect(
        Errors.message(error, 'move the item'),
        'Your Quark ran into a problem. Try again.',
      );
    });
  }
}
