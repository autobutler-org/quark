import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/api_explorer_config.dart';

/// What came back from a request the API explorer sent: the status, the
/// headers, and at most [ApiExplorerConfig.maxResponseBytes] of the body,
/// decoded leniently. [truncated] is true when the body was cut off there or
/// at [ApiExplorerConfig.maxResponseReadTime].
typedef ApiExplorerResponse = ({
  int statusCode,
  Map<String, String> headers,
  String body,
  bool truncated,
});

/// Sends the API explorer's "try it" requests (#4077) to any endpoint of the
/// active Quark, as the signed-in user: through [AuthenticatedService], so a
/// bearer token on native and the `session` cookie on web, and a 401 signs
/// the user out with [UnauthorizedException] like everywhere else.
///
/// The body is streamed and read only up to a cap, then the stream is
/// canceled, so a file download or the `/api/v0/events` stream costs at most
/// [ApiExplorerConfig.maxResponseBytes] of memory and
/// [ApiExplorerConfig.maxResponseReadTime] of waiting.
class ApiExplorerService with AuthenticatedService {
  /// Creates the service. Stateless, so any instance will do.
  ApiExplorerService();

  /// The URL a request to [pathTemplate] goes to: each `{name}` replaced by
  /// its value from [pathParameters], URI-encoded as one segment, and the
  /// non-empty [queryParameters] appended, against [base] (the active Quark
  /// by default).
  ///
  /// api: none
  static Uri resolveUri({
    required String pathTemplate,
    Map<String, String> pathParameters = const {},
    Map<String, String> queryParameters = const {},
    Uri? base,
  }) {
    final path = pathTemplate.replaceAllMapped(
      RegExp(r'\{([^}]+)\}'),
      (match) => Uri.encodeComponent(pathParameters[match[1]] ?? ''),
    );
    final query = {
      for (final MapEntry(:key, :value) in queryParameters.entries)
        if (value.isNotEmpty) key: value,
    };
    final uri = (base ?? apiBaseUri).resolve(path);
    return query.isEmpty ? uri : uri.replace(queryParameters: query);
  }

  /// Sends [method] to [uri], with [body] as JSON when given, and reads the
  /// answer up to the caps. An HTTP error status is an answer like any other;
  /// only a failure to send or read throws.
  ///
  /// api: none
  Future<ApiExplorerResponse> send({
    required String method,
    required Uri uri,
    String? body,
  }) async {
    final request = http.Request(method, uri);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = body;
    }
    final response = await authenticatedSend(request);
    final (bytes, truncated) = await _readCapped(response.stream);
    return (
      statusCode: response.statusCode,
      headers: response.headers,
      body: utf8.decode(bytes, allowMalformed: true),
      truncated: truncated,
    );
  }

  /// Reads [stream] until it ends, it passes the byte cap, or the read time
  /// runs out, then cancels it. Answers the bytes read and whether it stopped
  /// early.
  static Future<(Uint8List, bool)> _readCapped(Stream<List<int>> stream) {
    const cap = ApiExplorerConfig.maxResponseBytes;
    final bytes = BytesBuilder(copy: false);
    final done = Completer<(Uint8List, bool)>();
    late final StreamSubscription<List<int>> subscription;
    void finish(bool truncated) {
      if (done.isCompleted) return;
      unawaited(subscription.cancel());
      done.complete((bytes.takeBytes(), truncated));
    }

    final deadline = Timer(
      ApiExplorerConfig.maxResponseReadTime,
      () => finish(true),
    );
    subscription = stream.listen(
      (chunk) {
        final room = cap - bytes.length;
        bytes.add(chunk.length > room ? chunk.sublist(0, room) : chunk);
        if (chunk.length > room) finish(true);
      },
      onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
      onDone: () => finish(false),
      cancelOnError: true,
    );
    return done.future.whenComplete(deadline.cancel);
  }
}
