import 'package:flutter_test/flutter_test.dart';

import '../../scripts/generate_api_explorer_registry.dart' as gen;

/// A spec with two operations: one a fixture service calls, one it does not.
const _swagger = '''
{
  "basePath": "/api/v0",
  "paths": {
    "/widgets/{id}": {
      "get": {
        "tags": ["widgets"],
        "summary": "Get a widget",
        "parameters": [
          {"name": "id", "in": "path", "required": true, "type": "integer"}
        ],
        "responses": {
          "200": {"description": "OK", "schema": {"\$ref": "#/definitions/Widget"}}
        }
      },
      "delete": {"tags": ["widgets"], "summary": "Delete a widget"}
    }
  },
  "definitions": {
    "Widget": {"type": "object", "properties": {"name": {"type": "string"}}}
  }
}
''';

/// A service whose one method calls the spec's GET and an endpoint the spec
/// does not have.
const _service = r'''
class WidgetService with AuthenticatedService {
  /// Loads a widget and its parts.
  ///
  /// api: GET /api/v0/widgets/{id}
  /// api: GET /api/v0/widgets/{id}/parts
  static Future<void> load(int id) async {
    await instance.authenticatedGet(apiBaseUri.resolve('/api/v0/widgets/$id'));
    await instance.authenticatedGet(
      apiBaseUri.resolve('/api/v0/widgets/$id/parts'),
    );
  }
}
''';

void main() {
  test('the registry is the union of the spec and the service tags', () {
    final result = gen.generateRegistry(
      swaggerJson: _swagger,
      sources: const {'lib/services/widget_service.dart': _service},
    );

    expect(result.errors, isEmpty);
    final byKey = {
      for (final e in result.endpoints) '${e.method} ${e.path}': e,
    };
    expect(byKey.keys, [
      'GET /api/v0/widgets/{id}',
      'DELETE /api/v0/widgets/{id}',
      'GET /api/v0/widgets/{id}/parts',
    ]);

    // In both: the spec's entry plus its caller.
    final both = byKey['GET /api/v0/widgets/{id}']!;
    expect(both.spec, isNotNull);
    expect(both.callers, ['WidgetService.load']);
    // Swagger only: no caller.
    final specOnly = byKey['DELETE /api/v0/widgets/{id}']!;
    expect(specOnly.spec, isNotNull);
    expect(specOnly.callers, isEmpty);
    // Tag only: not in the spec.
    final tagOnly = byKey['GET /api/v0/widgets/{id}/parts']!;
    expect(tagOnly.spec, isNull);
    expect(tagOnly.callers, ['WidgetService.load']);

    // The $ref is resolved into the response schema.
    expect(
      result.source,
      contains(
        r'''schema: '{"type":"object","properties":{"name":{"type":"string"}}}',''',
      ),
    );
    expect(result.source, contains('inSwagger: false'));
  });

  test('an untagged HTTP call or a malformed tag fails with file:line', () {
    const untagged = r'''
class WidgetService with AuthenticatedService {
  /// Deletes a widget.
  static Future<void> delete(int id) =>
      instance.authenticatedDelete(apiBaseUri.resolve('/api/v0/widgets/$id'));

  /// Builds a URI; its callers name the endpoint.
  ///
  /// api: none
  static Uri _uri(String path) => apiBaseUri.resolve('/api/v0$path');

  /// Fetches a widget.
  ///
  /// api: FETCH /widgets
  static Future<void> fetch() async {}
}
''';
    final result = gen.generateRegistry(
      swaggerJson: _swagger,
      sources: const {'lib/services/widget_service.dart': untagged},
    );

    expect(result.errors, hasLength(2));
    expect(
      result.errors[0],
      startsWith(
        'lib/services/widget_service.dart:3: WidgetService.delete calls the '
        'Quark but its doc has no api: tag.',
      ),
    );
    expect(
      result.errors[1],
      startsWith(
        'lib/services/widget_service.dart:13: malformed tag '
        '"api: FETCH /widgets" on WidgetService.fetch.',
      ),
    );
  });
}
