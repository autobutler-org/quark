import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/chat_messages_service.dart';
import 'package:quark/utils/error_text.dart';

import '../support/fake_quark_http.dart';

/// What an attachment upload shows when the Quark refuses it (#4050).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  useFakeQuark();

  test('a 500 on upload shows the generic copy, not its body', () async {
    const body =
        'link /var/lib/quark/chat-attachments/1/.attachment-1 '
        '/var/lib/quark/chat-attachments/1/ab: operation not supported';
    answerWith((_) => http.Response(jsonEncode({'error': body}), 500));

    Object? thrown;
    try {
      await ChatMessagesService.putAttachment(1, 'ab' * 32, [1, 2, 3]);
    } catch (e) {
      thrown = e;
    }

    final text = Errors.message(thrown, 'upload the attachment');
    expect(
      text,
      Errors.message(const ApiException(500), 'upload the attachment'),
    );
    expect(text, isNot(contains('/var/lib')));
  });
}
