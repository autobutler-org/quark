import 'package:flutter/foundation.dart';

/// One endpoint of the Quark's API, as the API explorer lists it (#4077).
///
/// `lib/generated/api_explorer_registry.g.dart` builds every one of these from
/// two sources: the Swagger spec (`docs/swagger/swagger.json`) and the
/// `/// api: METHOD /api/v0/path` tags on the service methods in
/// `lib/services/`. An endpoint in both carries the spec's details and the
/// methods that call it. One only in the spec has no [callers]. One only in a
/// service has [inSwagger] false and nothing but its method, path and
/// [callers]: a missing or stale Swagger annotation.
@immutable
class ApiEndpoint {
  /// Creates an endpoint.
  const ApiEndpoint({
    required this.method,
    required this.path,
    required this.inSwagger,
    this.tags = const [],
    this.summary = '',
    this.description = '',
    this.parameters = const [],
    this.requestSchema,
    this.responses = const [],
    this.callers = const [],
  });

  /// The HTTP method, upper case: `GET`, `POST`, `PUT`, `PATCH` or `DELETE`.
  final String method;

  /// The full URL path the app calls, with path parameters in braces:
  /// `/api/v0/albums/{id}/items`.
  final String path;

  /// Whether the Swagger spec documents this endpoint.
  final bool inSwagger;

  /// The spec's tags, which group endpoints the way Swagger UI does. Empty
  /// when the endpoint is not in the spec.
  final List<String> tags;

  /// The spec's one-line summary.
  final String summary;

  /// The spec's longer description.
  final String description;

  /// Every parameter the spec lists, the body included.
  final List<ApiParameter> parameters;

  /// The JSON schema of the request body, with every `$ref` resolved, as a
  /// JSON string. Null when the endpoint takes no JSON body.
  final String? requestSchema;

  /// The documented responses, in the spec's order.
  final List<ApiResponse> responses;

  /// The service methods that call this endpoint, as `Service.method`. Empty
  /// when no service in the app calls it.
  final List<String> callers;
}

/// Where a request carries an [ApiParameter], as Swagger 2.0 names it.
enum ApiParameterLocation {
  /// A `{name}` segment of the path.
  path,

  /// A query-string parameter.
  query,

  /// The JSON request body; its shape is [ApiEndpoint.requestSchema].
  body,

  /// A request header.
  header,

  /// A multipart or URL-encoded form field.
  formData,
}

/// One parameter of an [ApiEndpoint].
@immutable
class ApiParameter {
  /// Creates a parameter.
  const ApiParameter({
    required this.name,
    required this.location,
    this.required = false,
    this.type = '',
    this.description = '',
  });

  /// The parameter's name.
  final String name;

  /// Where the request carries it.
  final ApiParameterLocation location;

  /// Whether the endpoint refuses a request without it.
  final bool required;

  /// The spec's type: `string`, `integer`, `boolean`, `file`, `array<string>`,
  /// or `object` for a body.
  final String type;

  /// The spec's description.
  final String description;
}

/// One documented response of an [ApiEndpoint].
@immutable
class ApiResponse {
  /// Creates a response.
  const ApiResponse({required this.status, this.description = '', this.schema});

  /// The status code as the spec writes it: `200`, `404`, or `default`.
  final String status;

  /// The spec's description of when this response comes back.
  final String description;

  /// The JSON schema of the body, with every `$ref` resolved, as a JSON
  /// string. Null when the spec gives none.
  final String? schema;
}
