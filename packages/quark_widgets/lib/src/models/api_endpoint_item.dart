import 'package:flutter/foundation.dart';

/// One endpoint of an HTTP API as `ApiEndpointList` and `ApiEndpointDetails`
/// show it: its method and path, what it is for, what it takes and returns,
/// and which client code calls it.
///
/// Schemas arrive as text the caller has already rendered, such as pretty
/// JSON, so the package never parses a spec.
@immutable
class ApiEndpointItem {
  /// Creates an endpoint's data.
  const ApiEndpointItem({
    required this.id,
    required this.method,
    required this.path,
    required this.tag,
    this.summary = '',
    this.description = '',
    this.parameters = const [],
    this.requestSchema,
    this.bodySkeleton,
    this.responses = const [],
    this.callers = const [],
    this.inSwagger = true,
  });

  /// Identifies the endpoint in callbacks and keys. Keep it key-safe, such as
  /// `get_api_v0_health`, so a `.probe` script can name it.
  final String id;

  /// The HTTP method, upper case: `GET`, `POST`, `PUT`, `PATCH`, `DELETE`.
  final String method;

  /// The path template, such as `/api/v0/files/{path}`.
  final String path;

  /// The group the endpoint is listed under, such as its Swagger tag.
  final String tag;

  /// The one-line summary beside the path. Empty hides it.
  final String summary;

  /// The longer description shown when expanded. Empty hides it.
  final String description;

  /// What the endpoint takes, in the order they are listed.
  final List<ApiParameterItem> parameters;

  /// The request body's schema as display text. Null hides it.
  final String? requestSchema;

  /// The text the "try it" body field starts with, such as an example JSON
  /// object. Null means the endpoint takes no body and hides the field.
  final String? bodySkeleton;

  /// The documented responses, one per status.
  final List<ApiResponseSchemaItem> responses;

  /// The client methods that call the endpoint, such as `FilesService.list`.
  /// Empty marks the endpoint "no client caller".
  final List<String> callers;

  /// Whether the API's spec documents it. False marks it "not in Swagger".
  final bool inSwagger;
}

/// Where a parameter of an [ApiEndpointItem] travels, after Swagger's `in`.
enum ApiParameterLocation {
  /// A segment of the path template.
  path,

  /// A query string parameter.
  query,

  /// The JSON request body.
  body,

  /// A request header.
  header,

  /// A multipart form field.
  formData,
}

/// One parameter an [ApiEndpointItem] takes.
@immutable
class ApiParameterItem {
  /// Creates a parameter's data.
  const ApiParameterItem({
    required this.name,
    required this.location,
    this.required = false,
    this.type = '',
    this.description = '',
  });

  /// The parameter's name. Also the source of its "try it" field's key.
  final String name;

  /// Where it travels. Only [ApiParameterLocation.path] and
  /// [ApiParameterLocation.query] get a "try it" field.
  final ApiParameterLocation location;

  /// Whether the endpoint needs it.
  final bool required;

  /// Its type as display text, such as `string` or `integer`. Empty hides it.
  final String type;

  /// What it is for. Empty hides it.
  final String description;
}

/// One documented response of an [ApiEndpointItem].
@immutable
class ApiResponseSchemaItem {
  /// Creates a response's data.
  const ApiResponseSchemaItem({
    required this.status,
    this.description = '',
    this.schema,
  });

  /// The status as the spec names it: `200`, `404`, or `default`.
  final String status;

  /// What the status means for this endpoint. Empty hides it.
  final String description;

  /// The body's schema as display text. Null hides it.
  final String? schema;
}

/// What the "try it" form of `ApiEndpointDetails` holds: one value per
/// path and query parameter, and the body.
@immutable
class ApiTryItInput {
  /// Creates the form's values.
  const ApiTryItInput({this.parameters = const {}, this.body});

  /// The typed value of each path and query parameter, by name. A parameter
  /// with no entry starts empty.
  final Map<String, String> parameters;

  /// The body as typed. Null means untouched, and the field starts from the
  /// endpoint's [ApiEndpointItem.bodySkeleton].
  final String? body;
}

/// A response the caller received after sending a request, as the response
/// panel of `ApiEndpointDetails` shows it.
@immutable
class ApiResponseItem {
  /// Creates a response's data.
  const ApiResponseItem({
    required this.statusCode,
    this.headers = const {},
    this.body = '',
    this.truncated = false,
  });

  /// The HTTP status code.
  final int statusCode;

  /// The response headers, by name.
  final Map<String, String> headers;

  /// The body as display text, such as pretty JSON. The caller caps it.
  final String body;

  /// Whether [body] is only the first part of what the server sent.
  final bool truncated;
}
