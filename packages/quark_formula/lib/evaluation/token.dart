/// The kinds of token the lexer produces.
enum TokenKind {
  number,
  string,
  boolean,
  ident,
  cellRef,
  colon,
  plus,
  minus,
  star,
  slash,
  percent,
  caret,
  eqEq,
  neq,
  lt,
  lte,
  gt,
  gte,
  lparen,
  rparen,
  comma,
  eof
}

/// One token from the lexer: its kind, its text, and where it starts in the formula.
class Token {
  final TokenKind kind;
  final String value;
  final int offset;

  Token({required this.kind, this.value = "", this.offset = 0});

  double? asNumber() {
    if (kind != TokenKind.number) {
      return null;
    }
    return double.tryParse(value);
  }

  /// Convert to JSON map. `kind` is serialized as its enum name.
  Map<String, dynamic> toJson() {
    return {
      'kind': kind.toString().split('.').last,
      'value': value,
      'offset': offset,
    };
  }

  /// Create [Token] from JSON map. Unknown or missing kinds default to TokenKind.eof.
  factory Token.fromJson(Map<String, dynamic> json) {
    final kindStr = json['kind'] as String? ?? '';
    final kind = TokenKind.values.firstWhere(
      (k) => k.toString().split('.').last == kindStr,
      orElse: () => TokenKind.eof,
    );
    final value = json['value']?.toString() ?? '';
    final offset = switch (json['offset']) {
      final int value => value,
      final num value => value.toInt(),
      final String value => int.tryParse(value) ?? 0,
      _ => 0,
    };
    return Token(kind: kind, value: value, offset: offset);
  }

  @override
  String toString() =>
      "Token(kind: ${kind.toString().split('.').last}, value: '$value', offset: $offset)";

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Token &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          value == other.value &&
          offset == other.offset;

  @override
  int get hashCode => Object.hash(kind, value, offset);
}
