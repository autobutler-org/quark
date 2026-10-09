import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/vault_backup_service.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark/utils/error_text.dart';

/// #1665: `POST /api/v0/vault/import-backup`, as the app calls and reads it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.Request>[];

  /// Answers every request with [status] and [body], recording it.
  void answer(int status, Object body) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode(body), status);
    });
  }

  Future<VaultRestoreResult> restore() => VaultBackupService.restoreFromDrive(
    deviceSerial: 'SN123',
    recoveryPassword: 'recovery words',
  );

  setUp(requests.clear);
  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  test('posts the drive and recovery password, and reads the counts', () async {
    answer(200, {
      'entriesImported': 3,
      'entriesSkipped': 2,
      'foldersImported': 1,
      'foldersSkipped': 4,
    });

    final result = await restore();

    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/v0/vault/import-backup');
    expect(jsonDecode(requests.single.body), {
      'deviceSerial': 'SN123',
      'recoveryPassword': 'recovery words',
    });
    expect(result.entriesImported, 3);
    expect(result.entriesSkipped, 2);
    expect(result.foldersImported, 1);
    expect(result.foldersSkipped, 4);
  });

  test('a count the Quark leaves out reads as zero', () async {
    answer(200, <String, Object>{});
    final result = await restore();
    expect(result.entriesImported, 0);
    expect(result.foldersSkipped, 0);
  });

  test('a locked vault throws VaultLockedException', () async {
    answer(423, {'error': 'vault is locked'});
    expect(restore(), throwsA(isA<VaultLockedException>()));
  });

  test("a rejected backup throws the status, not the Quark's text", () async {
    answer(400, {'error': 'import failed: incorrect recovery password'});
    Object? thrown;
    try {
      await restore();
    } catch (error) {
      thrown = error;
    }
    expect(thrown, isA<ApiException>());
    expect((thrown! as ApiException).statusCode, 400);
    expect(Errors.vaultRestore(thrown), Errors.vaultBackupRejected);
  });
}
