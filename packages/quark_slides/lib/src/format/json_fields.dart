/// Typed readers for the `.qslide` JSON tree, plus the deep equality the
/// model uses for the unknown fields it carries.
///
/// Every reader takes the path of the object it reads from, so a
/// [QslideFormatException] names exactly which value was wrong.
library;

import 'qslide_format_exception.dart';

/// A JSON object as decoded by `dart:convert`.
typedef JsonMap = Map<String, Object?>;

/// Reads [value] at [path] as a JSON object.
JsonMap asObject(Object? value, String path) {
  if (value is Map) return value.cast<String, Object?>();
  throw QslideFormatException('expected an object', path: path);
}

/// Reads [value] at [path] as a JSON array.
List<Object?> asList(Object? value, String path) {
  if (value is List) return value;
  throw QslideFormatException('expected an array', path: path);
}

/// Reads the required string [key] of [json].
String requireString(JsonMap json, String key, String path) {
  final value = json[key];
  if (value is String) return value;
  throw QslideFormatException('expected a string', path: '$path.$key');
}

/// Reads the optional string [key] of [json], or `null` when absent.
String? optionalString(JsonMap json, String key, String path) {
  final value = json[key];
  if (value == null || value is String) return value as String?;
  throw QslideFormatException('expected a string', path: '$path.$key');
}

/// Reads the required number [key] of [json] as a finite double.
double requireNumber(JsonMap json, String key, String path) {
  final value = optionalNumber(json, key, path);
  if (value != null) return value;
  throw QslideFormatException('expected a number', path: '$path.$key');
}

/// Reads the optional number [key] of [json], or `null` when absent.
double? optionalNumber(JsonMap json, String key, String path) {
  final value = json[key];
  if (value == null) return null;
  if (value is num && value.isFinite) return value.toDouble();
  throw QslideFormatException('expected a number', path: '$path.$key');
}

/// Reads the optional boolean [key] of [json], or [fallback] when absent.
bool optionalBool(JsonMap json, String key, String path, bool fallback) {
  final value = json[key];
  if (value == null) return fallback;
  if (value is bool) return value;
  throw QslideFormatException('expected a boolean', path: '$path.$key');
}

/// Reads the optional array [key] of [json], or an empty list when absent.
List<Object?> optionalList(JsonMap json, String key, String path) {
  final value = json[key];
  return value == null ? const [] : asList(value, '$path.$key');
}

/// Reads [key] of [json] as the name of one of [values], or [fallback] when
/// the key is absent or names a value this version does not know.
T enumByName<T extends Enum>(
  JsonMap json,
  String key,
  List<T> values,
  T fallback,
) {
  final name = json[key];
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

/// The entries of [json] whose keys are not in [known]: the fields a newer
/// writer added, kept so that saving the document again does not drop them.
JsonMap unknownFields(JsonMap json, Set<String> known) => Map.unmodifiable({
      for (final entry in json.entries)
        if (!known.contains(entry.key)) entry.key: entry.value,
    });

/// Writes [value] as an integer when it has no fractional part, so files
/// read `1920` rather than `1920.0`.
num jsonNumber(double value) =>
    value == value.truncateToDouble() ? value.toInt() : value;

/// Deep structural equality of two decoded JSON values.
bool jsonEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !jsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) return listEquals(a, b, jsonEquals);
  return a == b;
}

/// A hash consistent with [jsonEquals].
int jsonHash(Object? value) {
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map((e) => Object.hash(e.key, jsonHash(e.value))),
    );
  }
  if (value is List) return Object.hashAll(value.map(jsonHash));
  return value.hashCode;
}

/// Element-wise equality of two lists, comparing items with [equals] (`==`
/// by default).
bool listEquals<T>(
  List<T> a,
  List<T> b, [
  bool Function(T, T)? equals,
]) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!(equals?.call(a[i], b[i]) ?? a[i] == b[i])) return false;
  }
  return true;
}
