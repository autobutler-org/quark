import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// What [throwUnlessOk] throws for [status] and [body] under each flag:
/// the Quark's text as a [MessageException], or the bare status.
Object? _outcome(
  int status, {
  String body = '{"error":"name taken"}',
  bool serverText = true,
  bool clientErrorsOnly = false,
  bool genericForbidden = false,
  bool orMessage = false,
}) {
  try {
    throwUnlessOk(
      http.Response(body, status),
      'test',
      serverText: serverText,
      clientErrorsOnly: clientErrorsOnly,
      genericForbidden: genericForbidden,
      orMessage: orMessage,
    );
    return null;
  } on MessageException catch (e) {
    return e.message;
  } on ApiException catch (e) {
    return e.statusCode;
  }
}

void main() {
  test('a 2xx returns', () {
    expect(_outcome(200), isNull);
    expect(_outcome(204, body: ''), isNull);
  });

  test('the default shows the Quark\'s text for any refusal', () {
    expect(_outcome(400), 'name taken');
    expect(_outcome(403), 'name taken');
    expect(_outcome(500), 'name taken');
  });

  test('a body with no error text is the bare status', () {
    expect(_outcome(502, body: '<html>Bad Gateway</html>'), 502);
    expect(_outcome(409, body: ''), 409);
  });

  test('serverText false never shows the text', () {
    expect(_outcome(400, serverText: false), 400);
    expect(_outcome(500, serverText: false), 500);
  });

  test('clientErrorsOnly shows the text for a 4xx only', () {
    expect(_outcome(409, clientErrorsOnly: true), 'name taken');
    expect(_outcome(500, clientErrorsOnly: true), 500);
    expect(_outcome(302, clientErrorsOnly: true), 302);
  });

  test('genericForbidden answers a 403 with the status', () {
    expect(_outcome(403, genericForbidden: true), 403);
    expect(_outcome(409, genericForbidden: true), 'name taken');
  });

  test('orMessage falls back to a message field', () {
    const body = '{"message":"try later"}';
    expect(_outcome(429, body: body), 429);
    expect(_outcome(429, body: body, orMessage: true), 'try later');
  });
}
