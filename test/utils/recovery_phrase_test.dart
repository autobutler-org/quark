import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/chat_crypto.dart';
import 'package:quark/utils/recovery_phrase.dart';

/// #2430: the app generates the recovery phrase now, so its word list and
/// normalization have to be the Quark's.
void main() {
  test('the word list is the Go one, word for word', () {
    // `flutter test` runs from the repository root.
    final go = File('pkg/util/authutil/wordlist.go').readAsStringSync();
    final body = go.substring(go.indexOf('wordlist = []string{'));
    final words = [
      for (final match in RegExp(r'"([a-z]+)"').allMatches(body))
        match.group(1)!,
    ];

    expect(words, hasLength(256));
    expect(recoveryWords, words);
    expect(recoveryWords.toSet(), hasLength(256));
  });

  test('normalizing trims and lowercases, as NormalizeRecoveryPhrase does', () {
    expect(normalizeRecoveryPhrase('  Apple-BREAD\n'), 'apple-bread');
  });

  test('a generated phrase is six listed words joined by hyphens', () async {
    final crypto = await ChatCrypto.load();
    final phrases = {
      for (var i = 0; i < 8; i++) crypto.generateRecoveryPhrase(),
    };

    expect(phrases, hasLength(8));
    for (final phrase in phrases) {
      final words = phrase.split('-');
      expect(words, hasLength(recoveryPhraseWords));
      expect(words.every(recoveryWords.contains), isTrue, reason: phrase);
      expect(normalizeRecoveryPhrase(phrase), phrase);
    }
  });
}
