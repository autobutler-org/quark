import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What a [FakeIoQuark] answers one request with. [body] may be a future, in
/// which case the response waits for it after the request is sent.
typedef FakeIoReply = ({int status, FutureOr<String> body});

/// A Quark on the far side of `dart:io`, for the pages whose requests go
/// through the real `IOClient` rather than an injected `package:http` client.
///
/// Every request is recorded in [requested], then [answer] picks its reply.
/// [answer] may hold a request open (a future that completes late, or never)
/// or fail it (a future error, such as a `SocketException`).
///
/// ```dart
/// final quark = FakeIoQuark((method, url) async => (status: 200, body: '[]'));
/// await HttpOverrides.runZoned(() async {
///   ...
/// }, createHttpClient: quark.createHttpClient);
/// ```
class FakeIoQuark extends HttpOverrides {
  FakeIoQuark(this.answer);

  final Future<FakeIoReply> Function(String method, Uri url) answer;

  /// Every URL asked for, in order, recorded before it is answered.
  final List<Uri> requested = [];

  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(this);
}

class _Client implements HttpClient {
  _Client(this.quark);

  final FakeIoQuark quark;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    quark.requested.add(url);
    return _Request(url, await quark.answer(method, url));
  }

  // The rest of the client surface (connectionTimeout=, close(force:) and
  // the like) is irrelevant here, so it is swallowed rather than thrown.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.uri, this.reply);

  @override
  final Uri uri;
  final FakeIoReply reply;
  @override
  final HttpHeaders headers = _EmptyHeaders();

  @override
  Future<HttpClientResponse> close() async =>
      _Response(await reply.body, reply.status);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> flush() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response implements HttpClientResponse {
  _Response(this.body, this.statusCode);

  final String body;
  @override
  final int statusCode;
  @override
  int get contentLength => -1;
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  String get reasonPhrase => 'OK';
  @override
  List<Cookie> get cookies => const [];
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  final HttpHeaders headers = _EmptyHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable([utf8.encode(body)]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _EmptyHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
