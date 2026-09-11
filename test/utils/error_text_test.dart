import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

void main() {
  group('Errors.message', () {
    test('never returns the thrown object text', () {
      final leaky = Exception(
        'ClientException with SocketException: Connection refused (OS Error: '
        'Connection refused, errno = 61), address = quark.local, port = 51457',
      );
      final message = Errors.message(leaky, 'load remote access status');
      expect(message, "Couldn't load remote access status.");
      expect(message, isNot(contains('SocketException')));
      expect(message, isNot(contains('errno')));
    });

    test('an unreachable Quark gets the disconnected copy, not a failure', () {
      expect(
        Errors.message(http.ClientException('Connection refused'), 'load'),
        quarkDisconnectedInline,
      );
      expect(
        Errors.message(TimeoutException('no answer'), 'load'),
        quarkDisconnectedInline,
      );
    });

    test('maps the statuses the Quark actually returns', () {
      expect(
        Errors.message(const ApiException(403), 'delete the album'),
        "You don't have permission to delete the album.",
      );
      expect(
        Errors.message(const ApiException(404), 'open the file'),
        contains('no longer there'),
      );
      expect(
        Errors.message(const ApiException(500), 'save the document'),
        'Your Quark ran into a problem. Try again.',
      );
      expect(
        Errors.message(const ApiException(401), 'save the document'),
        Errors.sessionExpired,
      );
    });

    test('a 401 from the shared client says the session is gone', () {
      expect(
        Errors.message(const UnauthorizedException(), 'load your files'),
        Errors.sessionExpired,
      );
    });

    test('falls back to the action for a status with no special copy', () {
      expect(
        Errors.message(const ApiException(418), 'brew the coffee'),
        "Couldn't brew the coffee.",
      );
    });

    test('passes the Quark\'s own copy through as a sentence', () {
      expect(
        Errors.message(
          const MessageException('server busy, please retry'),
          'load your photos',
        ),
        'Server busy, please retry.',
      );
      expect(
        Errors.message(const MessageException('Invalid credentials.'), 'x'),
        'Invalid credentials.',
      );
    });

    test('a failure recorded without an error still gets a sentence', () {
      expect(
        Errors.message(null, 'upload cat.jpg'),
        "Couldn't upload cat.jpg.",
      );
    });
  });

  group('Errors.restore', () {
    test('a 409 says the original location is taken', () {
      expect(
        Errors.restore(const ApiException(409), 'restore the item'),
        Errors.restoreConflict,
      );
    });

    test('anything else reads like Errors.message', () {
      expect(
        Errors.restore(const ApiException(404), 'restore the item'),
        Errors.message(const ApiException(404), 'restore the item'),
      );
      expect(
        Errors.restore(Exception('boom'), 'restore the item'),
        "Couldn't restore the item.",
      );
    });
  });

  group('throwApiError', () {
    test('prefers the Quark\'s message when it sent one', () {
      expect(
        () => throwApiError(503, 'server busy, please retry', 'Mount failed'),
        throwsA(
          isA<MessageException>().having(
            (e) => e.message,
            'message',
            'server busy, please retry',
          ),
        ),
      );
    });

    test('falls back to the status when the body carried no message', () {
      expect(
        () => throwApiError(500, null, 'Mount failed'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });
  });

  // The rule this file exists to keep: error copy comes from Errors, never
  // from a string literal at the call site (#1622). A single missed `$e` is
  // how the raw SocketException dump reached the settings page.
  test('no user-facing string interpolates a thrown object', () {
    final offenders = <String>[];
    final userFacing = RegExp(
      r"""(Text|_showMessage|SnackBar)\(\s*'[^']*\$\{?(e|err|error)\b""",
    );

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('debugPrint')) continue;
        if (userFacing.hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use Errors.message(error, "do the thing") instead of putting a '
          'thrown object into text a user reads.',
    );
  });
}
