import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/connection_error.dart';

/// A Quark that accepts the connection and then says nothing — the case the
/// OS is happy to wait tens of seconds on (#1712).
class _SilentClient extends http.BaseClient {
  final _never = Completer<http.StreamedResponse>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _never.future;
}

void main() {
  testWidgets('checkStatus gives up on a silent Quark within the timeout', (
    tester,
  ) async {
    authHttpClientFactory = () => _SilentClient();
    addTearDown(() => authHttpClientFactory = () => sharedHttpClient);

    Object? error;
    unawaited(
      AuthService.checkStatus().then((_) {}, onError: (Object e) => error = e),
    );

    await tester.pump(kAuthRequestTimeout ~/ 2);
    expect(error, isNull, reason: 'must not give up before the deadline');

    await tester.pump(kAuthRequestTimeout);
    expect(error, isA<TimeoutException>());
    expect(isQuarkUnreachableError(error!), isTrue);
  });
}
