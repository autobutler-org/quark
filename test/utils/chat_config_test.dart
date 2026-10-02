import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/chat_config.dart';

/// The composer's length limit (#2503) keeps every message it lets through
/// under the Quark's ciphertext cap, whatever the message is made of.
void main() {
  test('the longest message fits the ciphertext cap in any script', () {
    const n = ChatConfig.maxMessageLength;
    for (final unit in ['a', 'é', '中', '😀']) {
      final text = unit * (n ~/ unit.length);
      expect(text.length, lessThanOrEqualTo(n));
      expect(
        utf8.encode(text).length + ChatConfig.ciphertextOverheadBytes,
        lessThanOrEqualTo(ChatConfig.maxCiphertextBytes),
        reason: unit,
      );
    }
  });
}
