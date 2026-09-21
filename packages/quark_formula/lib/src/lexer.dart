// Minimal lexer placeholder for quark_formula package

/// The prototype engine's lexer.
class Lexer {
  final String input;
  Lexer(this.input);

  Iterable<String> tokenize() sync* {
    if (input.isEmpty) return;
    // very naive tokenization for placeholder purposes
    final parts = input.split(RegExp(r"\s+"));
    for (final p in parts) {
      if (p.isNotEmpty) yield p;
    }
  }
}
