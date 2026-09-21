// Builtin functions and constants for formula engine

/// The prototype engine's built-in constants. The sheets editor's functions live in
/// `evaluation/evaluator/builtins.dart`.
final Map<String, Function> builtins = {
  'PI': () => 3.141592653589793,
  'E': () => 2.718281828459045,
};
