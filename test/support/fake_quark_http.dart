import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';

/// Every request the shared client sent since the test began, oldest first.
final requests = <http.Request>[];

/// Starts every test in the enclosing group with no [requests], and puts the
/// real shared client back after each one. Call it once, where the file
/// declares its `setUp`s.
void useFakeQuark() {
  setUp(requests.clear);
  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });
}

/// Answers each request through the shared client with what [respond]
/// returns for it, recording it in [requests].
void answerWith(
  FutureOr<http.Response> Function(http.Request request) respond,
) {
  resetSharedHttpClient();
  sharedHttpClientFactory = () => MockClient((request) async {
    requests.add(request);
    return respond(request);
  });
}

/// Answers every request with [status] and [body] as JSON, recording it.
void answer(int status, Object? body) =>
    answerWith((_) => http.Response(jsonEncode(body), status));
