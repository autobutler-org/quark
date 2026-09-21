/// Raised when a formula contains text the lexer cannot turn into tokens.
class LexError implements Exception {
  final String message;
  final int offset;

  LexError(this.message, {required this.offset});

  @override
  String toString() => 'LexError(offset: $offset, message: $message)';
}
