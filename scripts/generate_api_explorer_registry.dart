// Generates lib/generated/api_explorer_registry.g.dart, the endpoint list the
// in-app API explorer shows (#4077), from two sources:
//
// 1. docs/swagger/swagger.json, the spec the backend's annotations produce;
// 2. the `/// api: METHOD /api/v0/path` tags on the members of lib/services/.
//
// An endpoint is the union of both: the spec's details, plus the service
// members whose tags name it.
//
// Finding the calls is a doc tag rather than an analysis of URI expressions,
// because many services build their paths at runtime. What keeps the tags
// honest is a deliberately simple heuristic: a member (method, getter or
// function) "calls the Quark" when its body, outside comments,
//
//   - calls authenticatedGet/Post/Put/Patch/Delete/Send/Download,
//   - names an HTTP client (an identifier containing `HttpClient`, or
//     `httpClient`) or `window.fetch`,
//   - calls http.get/post/put/patch/delete/head/read/readBytes, or
//   - has a string literal containing `/api/v0`.
//
// Such a member needs at least one tag, and generation fails, naming the
// file and line, when it has none. A member that names no endpoint of its own
// says so with `/// api: none`: a helper whose callers carry the tag because
// they pass it the path, a URI builder, the transport in
// authenticated_service.dart, or a request that is not to the Quark at all
// (a dropped file's blob URL). A false positive is fixed the same way.
//
// What the heuristic does not see: a field's initializer, a constructor's
// initializer list, and a call through a parameter of a type of its own
// (`source.putRange(...)`). Tag such a caller by hand; a tag on any member is
// read, whether the heuristic flagged it or not.
//
// Like scripts/generate_flutter_sbom.dart this imports only dart: libraries,
// so it runs under plain `dart`, and it is a scanner rather than
// package:analyzer, which the app does not depend on.
//
// Run with `make generate/frontend/api-explorer`.
library;

import 'dart:convert';
import 'dart:io';

/// The spec this reads, relative to the repository root.
const String swaggerPath = 'docs/swagger/swagger.json';

/// The directory whose members' tags this reads.
const String servicesDir = 'lib/services';

/// The file this writes.
const String outputPath = 'lib/generated/api_explorer_registry.g.dart';

/// The methods a tag may name, in the order an endpoint's methods are listed.
const List<String> httpMethods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

/// The prefix every tagged path starts with: the spec's `basePath`.
const String apiPrefix = '/api/v0';

void main() {
  final swagger = File(swaggerPath);
  if (!swagger.existsSync()) {
    stderr.writeln(
      '$swaggerPath not found. Run `make generate/backend/swagger` first.',
    );
    exit(1);
  }
  final sources = <String, String>{
    for (final file in Directory(
      servicesDir,
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart')))
      file.path: file.readAsStringSync(),
  };
  final result = generateRegistry(
    swaggerJson: swagger.readAsStringSync(),
    sources: sources,
  );
  if (result.errors.isNotEmpty) {
    result.errors.forEach(stderr.writeln);
    stderr.writeln(
      '\n${result.errors.length} problem(s) in the api: tags; $outputPath was '
      'not written. A path is the $swaggerPath key with $apiPrefix in front.',
    );
    exit(1);
  }
  File(outputPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(result.source);
  stdout.writeln('Wrote $outputPath (${result.endpoints.length} endpoints).');
}

/// The outcome of [generateRegistry].
class RegistryResult {
  /// Creates a result.
  const RegistryResult(this.endpoints, this.errors, this.source);

  /// Every endpoint, sorted by path and then method.
  final List<Endpoint> endpoints;

  /// One `file:line: what is wrong and how to fix it` line per problem.
  final List<String> errors;

  /// The Dart source of the registry; meaningless when [errors] is not empty.
  final String source;
}

/// One endpoint as the generator builds it: [spec] is the spec's operation,
/// null when only a tag names it.
class Endpoint {
  /// Creates an endpoint.
  Endpoint(this.method, this.path, this.spec);

  /// The upper-case HTTP method.
  final String method;

  /// The full path, `/api/v0/...`.
  final String path;

  /// The spec's operation object, or null when it is not in the spec.
  final Map<String, dynamic>? spec;

  /// The `Service.member` names whose tags name this endpoint.
  final List<String> callers = [];
}

/// One `api:` tag, or a member that calls the Quark without one.
class ServiceMember {
  /// Creates a member.
  const ServiceMember({
    required this.file,
    required this.line,
    required this.name,
    required this.tags,
    required this.callsQuark,
  });

  /// The file it is declared in.
  final String file;

  /// The line its declaration starts on.
  final int line;

  /// `Class.member`, or the bare name of a top-level function.
  final String name;

  /// The text after `api:` on each tag line of its doc, trimmed.
  final List<({int line, String text})> tags;

  /// Whether the heuristic says its body calls the Quark.
  final bool callsQuark;
}

/// Builds the registry from [swaggerJson] and the service [sources] (path to
/// contents). Pure, so the test feeds it fixtures.
RegistryResult generateRegistry({
  required String swaggerJson,
  required Map<String, String> sources,
}) {
  final spec = jsonDecode(swaggerJson) as Map<String, dynamic>;
  final basePath = spec['basePath'] as String? ?? '';
  final definitions =
      spec['definitions'] as Map<String, dynamic>? ?? const <String, dynamic>{};
  final endpoints = <String, Endpoint>{};
  final paths = spec['paths'] as Map<String, dynamic>? ?? const {};
  for (final MapEntry(key: path, value: ops) in paths.entries) {
    for (final MapEntry(key: method, value: op)
        in (ops as Map<String, dynamic>).entries) {
      final upper = method.toUpperCase();
      if (!httpMethods.contains(upper)) continue;
      final full = '$basePath$path';
      endpoints['$upper $full'] = Endpoint(
        upper,
        full,
        op as Map<String, dynamic>,
      );
    }
  }

  final errors = <String>[];
  final tagPattern = RegExp(
    '^(${httpMethods.join('|')}) (${RegExp.escape(apiPrefix)}'
    r'(?:/(?:[A-Za-z0-9_.\-]+|\{[A-Za-z_]\w*\}))+)$',
  );
  for (final file in sources.keys.toList()..sort()) {
    for (final member in scanMembers(sources[file]!, file)) {
      if (member.callsQuark && member.tags.isEmpty) {
        errors.add(
          '${member.file}:${member.line}: ${member.name} calls the Quark but '
          'its doc has no api: tag. Add "/// api: METHOD $apiPrefix/path" for '
          'each endpoint it calls, or "/// api: none" when it names no '
          'endpoint of its own (its callers do, or it does not call the '
          'Quark).',
        );
      }
      for (final tag in member.tags) {
        if (tag.text == 'none') continue;
        final match = tagPattern.firstMatch(tag.text);
        if (match == null) {
          errors.add(
            '${member.file}:${tag.line}: malformed tag "api: ${tag.text}" on '
            '${member.name}. Write "api: METHOD $apiPrefix/path" with METHOD '
            'one of ${httpMethods.join(', ')} and path parameters as {name}, '
            'or "api: none".',
          );
          continue;
        }
        final key = '${match[1]} ${match[2]}';
        final endpoint = endpoints[key] ??= Endpoint(
          match[1]!,
          match[2]!,
          null,
        );
        if (!endpoint.callers.contains(member.name)) {
          endpoint.callers.add(member.name);
        }
      }
    }
  }

  final sorted = endpoints.values.toList()
    ..sort((a, b) {
      final byPath = a.path.compareTo(b.path);
      return byPath != 0
          ? byPath
          : httpMethods.indexOf(a.method) - httpMethods.indexOf(b.method);
    });
  for (final e in sorted) {
    e.callers.sort();
  }
  return RegistryResult(sorted, errors, _render(sorted, definitions));
}

/// Splits [source] into its members (recursing into classes, mixins,
/// extensions and enums) and reports each that has an `api:` tag or that the
/// heuristic says calls the Quark.
List<ServiceMember> scanMembers(String source, String file) {
  final code = _mask(source, keepStrings: false);
  final noComments = _mask(source, keepStrings: true);
  final members = <ServiceMember>[];
  int lineOf(int offset) =>
      '\n'.allMatches(source.substring(0, offset)).length + 1;
  final docPattern = RegExp(r'^[ \t]*///[ \t]*api:(.*)$', multiLine: true);

  // One member spans [start, end); its body starts at [bodyStart].
  void add(int start, int bodyStart, int end, String? owner) {
    final header = code.substring(start, bodyStart);
    final declaration = header.indexOf(RegExp(r'\S'));
    final name = _memberName(header);
    if (declaration < 0 || name == null) return;
    final callsQuark =
        _callPattern.hasMatch(code.substring(bodyStart, end)) ||
        noComments.substring(bodyStart, end).contains(apiPrefix);
    final tags = [
      for (final m in docPattern.allMatches(source.substring(start, bodyStart)))
        (line: lineOf(start + m.start), text: m[1]!.trim()),
    ];
    if (!callsQuark && tags.isEmpty) return;
    members.add(
      ServiceMember(
        file: file,
        line: lineOf(start + declaration),
        name: owner == null ? name : '$owner.$name',
        tags: tags,
        callsQuark: callsQuark,
      ),
    );
  }

  void scan(int start, int end, String? owner) {
    var segment = start;
    var parens = 0;
    for (var i = start; i < end; i++) {
      final c = code[i];
      if (c == '(' || c == '[') parens++;
      if (c == ')' || c == ']') parens--;
      if (parens != 0) continue;
      if (c == ';') {
        // An expression body starts at its arrow; a field has no body.
        final arrow = code.indexOf('=>', segment);
        add(segment, arrow >= 0 && arrow < i ? arrow : i, i + 1, owner);
        segment = i + 1;
      } else if (c == '{') {
        final close = _matchingBrace(code, i);
        final header = code.substring(segment, i);
        if (header.contains('=>')) {
          // An expression body holding a brace (a map or a switch): the
          // member runs on to its semicolon.
          i = close;
          continue;
        }
        final kind = RegExp(
          r'\b(class|mixin|extension|enum)\s+(\w+)?',
        ).firstMatch(header);
        if (kind != null) {
          scan(i + 1, close, kind[1] == 'extension' ? owner : kind[2]);
        } else {
          add(segment, i, close + 1, owner);
        }
        segment = close + 1;
        i = close;
      }
    }
  }

  scan(0, code.length, null);
  return members;
}

/// The calls that mark a member as calling the Quark; see the file comment.
final RegExp _callPattern = RegExp(
  r'\bauthenticated(Get|Post|Put|Patch|Delete|Send|Download)\s*\('
  r'|\w*HttpClient\w*|\bhttpClient\b|\bwindow\s*\.\s*fetch\b'
  r'|\bhttp\s*\.\s*(get|post|put|patch|delete|head|read|readBytes)\s*\(',
);

/// The name a member's [header] (its text up to the body) declares: a getter
/// or setter's name, else the identifier before the first parenthesis.
/// Null for a field, whose initializer is not checked.
String? _memberName(String header) {
  final stripped = header.replaceAll(RegExp(r'@[\w.]+(\s*\([^)]*\))?'), ' ');
  var outer = stripped;
  for (var prev = ''; prev != outer;) {
    prev = outer;
    outer = outer.replaceAll(RegExp(r'\([^()]*\)'), '');
  }
  if (RegExp(r'\w\s*=(?![=>])').hasMatch(outer)) return null;
  final accessor = RegExp(
    r'\b(?:get|set)\s+(\w+)\s*(?:=>|\(|$)',
  ).firstMatch(stripped.trimRight());
  if (accessor != null) return accessor[1];
  return RegExp(r'(\w+)\s*(?:<[^()]*>)?\s*\(').firstMatch(stripped)?[1];
}

/// The index of the `}` that closes the `{` at [open] in masked [code].
int _matchingBrace(String code, int open) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    if (code[i] == '{') depth++;
    if (code[i] == '}' && --depth == 0) return i;
  }
  return code.length - 1;
}

/// [source] with every comment blanked, and every string literal too unless
/// [keepStrings], leaving line breaks so offsets and lines still match.
String _mask(String source, {required bool keepStrings}) {
  final out = source.codeUnits.toList();
  void blank(int from, int to) {
    for (var k = from; k < to && k < out.length; k++) {
      if (out[k] != 0x0A) out[k] = 0x20;
    }
  }

  bool isIdent(int i) => i >= 0 && RegExp(r'[A-Za-z0-9_$]').hasMatch(source[i]);

  late int Function(int) string;
  // Scans code from [i]; inside an interpolation it stops after the `}` that
  // closes it.
  int code(int i, {bool interpolation = false}) {
    var depth = 0;
    while (i < source.length) {
      final c = source[i];
      if (source.startsWith('//', i)) {
        final end = source.indexOf('\n', i);
        final stop = end < 0 ? source.length : end;
        blank(i, stop);
        i = stop;
      } else if (source.startsWith('/*', i)) {
        var nest = 0;
        var j = i;
        while (j < source.length) {
          if (source.startsWith('/*', j)) {
            nest++;
            j += 2;
          } else if (source.startsWith('*/', j)) {
            j += 2;
            if (--nest == 0) break;
          } else {
            j++;
          }
        }
        blank(i, j);
        i = j;
      } else if (c == "'" ||
          c == '"' ||
          (c == 'r' &&
              i + 1 < source.length &&
              (source[i + 1] == "'" || source[i + 1] == '"') &&
              !isIdent(i - 1))) {
        final end = string(i);
        if (!keepStrings) blank(i, end);
        i = end;
      } else {
        if (interpolation && c == '{') depth++;
        if (interpolation && c == '}' && depth-- == 0) return i + 1;
        i++;
      }
    }
    return i;
  }

  string = (int i) {
    final raw = source[i] == 'r';
    if (raw) i++;
    final quote = source[i];
    final triple = source.startsWith(quote * 3, i);
    i += triple ? 3 : 1;
    while (i < source.length) {
      if (!raw && source[i] == r'\') {
        i += 2;
      } else if (!raw && source.startsWith(r'${', i)) {
        i = code(i + 2, interpolation: true);
      } else if (triple
          ? source.startsWith(quote * 3, i)
          : source[i] == quote) {
        return i + (triple ? 3 : 1);
      } else if (!triple && source[i] == '\n') {
        return i;
      } else {
        i++;
      }
    }
    return i;
  };

  code(0);
  return String.fromCharCodes(out);
}

/// The registry's Dart source.
String _render(List<Endpoint> endpoints, Map<String, dynamic> definitions) {
  final b = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln(
      '// Generated by scripts/generate_api_explorer_registry.dart from',
    )
    ..writeln('// $swaggerPath and the api: tags in $servicesDir/.')
    ..writeln('// Run `make generate/frontend/api-explorer` to regenerate.')
    ..writeln('//')
    ..writeln('// The formatter is off so that the generator alone decides')
    ..writeln('// the layout and CI can diff it.')
    ..writeln('// dart format off')
    ..writeln()
    ..writeln('/// Every endpoint the API explorer lists (#4077): the union of')
    ..writeln('/// the Swagger spec and the service tags, sorted by path and')
    ..writeln('/// then method.')
    ..writeln('library;')
    ..writeln()
    ..writeln("import 'package:quark/models/api_endpoint.dart';")
    ..writeln()
    ..writeln('/// Every endpoint, sorted by path and then method.')
    ..writeln('const List<ApiEndpoint> apiEndpoints = [');
  for (final e in endpoints) {
    final op = e.spec;
    b
      ..writeln('  ApiEndpoint(')
      ..writeln('    method: ${_dart(e.method)},')
      ..writeln('    path: ${_dart(e.path)},')
      ..writeln('    inSwagger: ${op != null},');
    if (op != null) {
      final tags = (op['tags'] as List? ?? const []).cast<String>();
      if (tags.isNotEmpty) {
        b.writeln('    tags: [${tags.map(_dart).join(', ')}],');
      }
      final summary = op['summary'] as String? ?? '';
      if (summary.isNotEmpty) b.writeln('    summary: ${_dart(summary)},');
      final description = op['description'] as String? ?? '';
      if (description.isNotEmpty) {
        b.writeln('    description: ${_dart(description)},');
      }
      final params = (op['parameters'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      if (params.isNotEmpty) {
        b.writeln('    parameters: [');
        for (final p in params) {
          b
            ..writeln('      ApiParameter(')
            ..writeln('        name: ${_dart(p['name'] as String)},')
            ..writeln(
              '        location: ApiParameterLocation.${p['in'] as String},',
            );
          if (p['required'] == true) b.writeln('        required: true,');
          b.writeln('        type: ${_dart(_paramType(p))},');
          final pd = p['description'] as String? ?? '';
          if (pd.isNotEmpty) b.writeln('        description: ${_dart(pd)},');
          b.writeln('      ),');
        }
        b.writeln('    ],');
      }
      final body = params.where((p) => p['in'] == 'body').firstOrNull;
      if (body?['schema'] != null) {
        b.writeln(
          '    requestSchema: ${_dart(_schemaJson(body!['schema'], definitions))},',
        );
      }
      final responses =
          op['responses'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      if (responses.isNotEmpty) {
        b.writeln('    responses: [');
        for (final MapEntry(key: status, value: r) in responses.entries) {
          final response = r as Map<String, dynamic>;
          b
            ..writeln('      ApiResponse(')
            ..writeln('        status: ${_dart(status)},');
          final rd = response['description'] as String? ?? '';
          if (rd.isNotEmpty) b.writeln('        description: ${_dart(rd)},');
          if (response['schema'] != null) {
            b.writeln(
              '        schema: ${_dart(_schemaJson(response['schema'], definitions))},',
            );
          }
          b.writeln('      ),');
        }
        b.writeln('    ],');
      }
    }
    if (e.callers.isNotEmpty) {
      b.writeln('    callers: [${e.callers.map(_dart).join(', ')}],');
    }
    b.writeln('  ),');
  }
  b.writeln('];');
  return b.toString();
}

/// A parameter's type as [ApiParameter.type] documents it.
String _paramType(Map<String, dynamic> p) {
  final type = p['type'] as String?;
  if (type == 'array') {
    final items = p['items'] as Map<String, dynamic>?;
    return 'array<${items?['type'] ?? 'object'}>';
  }
  if (type != null) return type;
  final schema = p['schema'] as Map<String, dynamic>?;
  return schema?['type'] as String? ?? 'object';
}

/// [schema] as compact JSON, with each `$ref` replaced by the definition it
/// names. A definition that refers back to itself stays a `$ref` the second
/// time round, so recursion ends.
String _schemaJson(Object? schema, Map<String, dynamic> definitions) {
  Object? resolve(Object? node, Set<String> seen) {
    if (node is List) return [for (final n in node) resolve(n, seen)];
    if (node is! Map<String, dynamic>) return node;
    final ref = node[r'$ref'] as String?;
    if (ref != null) {
      final name = ref.split('/').last;
      final target = definitions[name];
      if (target == null || seen.contains(name)) return node;
      return resolve(target, {...seen, name});
    }
    return {for (final e in node.entries) e.key: resolve(e.value, seen)};
  }

  return jsonEncode(resolve(schema, const {}));
}

/// [value] as a single-quoted Dart string literal.
String _dart(String value) {
  final b = StringBuffer("'");
  for (final rune in value.runes) {
    switch (rune) {
      case 0x5C:
        b.write(r'\\');
      case 0x27:
        b.write(r"\'");
      case 0x24:
        b.write(r'\$');
      case 0x0A:
        b.write(r'\n');
      case 0x0D:
        b.write(r'\r');
      case 0x09:
        b.write(r'\t');
      default:
        b.write(
          rune < 0x20
              ? '\\u{${rune.toRadixString(16)}}'
              : String.fromCharCode(rune),
        );
    }
  }
  b.write("'");
  return b.toString();
}
