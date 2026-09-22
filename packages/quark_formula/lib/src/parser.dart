// Minimal parser placeholder for quark_formula package

/// The prototype engine's parser.
class Parser {
  final Iterable<String> tokens;
  Parser(this.tokens);

  /// Returns a trivial AST representation (list of tokens)
  List<String> parse() => tokens.toList();
}
