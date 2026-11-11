import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:quark/generated/api_explorer_registry.g.dart'
    deferred as registry;
import 'package:quark/models/api_endpoint.dart' as model;
import 'package:quark/services/api_explorer_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/json_schema_sample.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Sends one request the explorer built, as [ApiExplorerService.send] does.
typedef ApiExplorerSend =
    Future<ApiExplorerResponse> Function({
      required String method,
      required Uri uri,
      String? body,
    });

/// The state of the API explorer page (#4077): every endpoint the generated
/// registry lists, mapped into the package's [ApiEndpointItem]s, the search,
/// which endpoint is expanded, and for each endpoint what its "try it" form
/// holds and what its last request came back with.
///
/// The registry is a deferred library, about 600 KB of source, so the web
/// build fetches it only when the page opens. Loading it and sending a
/// request arrive as function parameters defaulting to the real ones, so a
/// test passes fakes without a mocking library.
///
/// It never asks the user anything: the page confirms a request that changes
/// data ([needsConfirmation]) before calling [send].
class ApiExplorerController extends ChangeNotifier with SafeNotifier {
  /// Creates a controller reading the real registry and sending through
  /// [ApiExplorerService] unless overridden.
  ApiExplorerController({
    Future<List<model.ApiEndpoint>> Function() loadEndpoints = _loadRegistry,
    ApiExplorerSend? send,
  }) : _loadEndpoints = loadEndpoints,
       _send = send ?? ApiExplorerService().send;

  /// The group an endpoint the Swagger spec does not document is listed
  /// under, after every Swagger tag.
  static const notInSwaggerTag = 'Not in Swagger';

  final Future<List<model.ApiEndpoint>> Function() _loadEndpoints;
  final ApiExplorerSend _send;

  bool _isLoading = true;
  String? _loadError;
  List<ApiEndpointItem> _endpoints = const [];
  Map<String, String> _searchText = const {};
  String _query = '';
  String? _expandedId;
  final Map<String, ApiTryItInput> _inputs = {};
  final Set<String> _sending = {};
  final Map<String, ApiResponseItem> _responses = {};
  final Map<String, String> _errors = {};

  /// Whether the registry is still loading.
  bool get isLoading => _isLoading;

  /// Why the registry could not be loaded, from [Errors], or null.
  String? get loadError => _loadError;

  /// What the search box holds.
  String get query => _query;

  /// The id of the expanded endpoint, or null.
  String? get expandedId => _expandedId;

  /// The expanded endpoint, or null.
  ApiEndpointItem? get expanded =>
      _endpoints.where((e) => e.id == _expandedId).firstOrNull;

  /// The endpoints the search leaves, grouped by tag: Swagger tags in
  /// alphabetical order, then [notInSwaggerTag], each in path order.
  List<ApiEndpointItem> get visibleEndpoints {
    final terms = _query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((term) => term.isEmpty);
    return [
      for (final endpoint in _endpoints)
        if (terms.every(_searchText[endpoint.id]!.contains)) endpoint,
    ];
  }

  /// Reads the registry. Call once, when the page opens.
  Future<void> load() async {
    try {
      final byTag = <String, List<ApiEndpointItem>>{};
      final search = <String, String>{};
      for (final endpoint in await _loadEndpoints()) {
        final item = _toItem(endpoint);
        (byTag[item.tag] ??= []).add(item);
        search[item.id] = [
          endpoint.method,
          endpoint.path,
          endpoint.summary,
          ...endpoint.tags,
          ...endpoint.callers,
        ].join('\n').toLowerCase();
      }
      final notInSwagger = byTag.remove(notInSwaggerTag);
      _endpoints = [
        for (final tag in byTag.keys.toList()..sort()) ...byTag[tag]!,
        ...?notInSwagger,
      ];
      _searchText = search;
    } catch (error) {
      _loadError = Errors.message(error, 'load the list of endpoints');
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Filters the list to the endpoints whose method, path, summary, tags or
  /// callers hold every word of [query].
  void search(String query) {
    _query = query;
    notifyListeners();
  }

  /// Expands the endpoint [id], or collapses it when it is the expanded one.
  void toggle(String id) {
    _expandedId = _expandedId == id ? null : id;
    notifyListeners();
  }

  /// What the "try it" form of [id] holds, kept across the row being
  /// collapsed or scrolled away.
  ApiTryItInput inputFor(String id) => _inputs[id] ?? const ApiTryItInput();

  /// Keeps what the "try it" form of [id] holds. The form shows the edit
  /// itself, so nothing is rebuilt.
  void updateInput(String id, ApiTryItInput input) => _inputs[id] = input;

  /// Whether a request to [id] is in flight.
  bool isSending(String id) => _sending.contains(id);

  /// What the last request to [id] came back with, or null.
  ApiResponseItem? responseFor(String id) => _responses[id];

  /// Why the last request to [id] could not be sent, from [Errors], or null.
  String? errorFor(String id) => _errors[id];

  /// Whether a request to [id] can change data, so the page asks first:
  /// anything but a GET.
  bool needsConfirmation(String id) => _endpoint(id).method != 'GET';

  /// The URL a request to [id] with [input] goes to.
  Uri requestUri(String id, ApiTryItInput input) {
    final endpoint = _endpoint(id);
    Map<String, String> valuesIn(ApiParameterLocation location) => {
      for (final parameter in endpoint.parameters)
        if (parameter.location == location)
          parameter.name: input.parameters[parameter.name] ?? '',
    };
    return ApiExplorerService.resolveUri(
      pathTemplate: endpoint.path,
      pathParameters: valuesIn(ApiParameterLocation.path),
      queryParameters: valuesIn(ApiParameterLocation.query),
    );
  }

  /// Sends a request to [id] with [input]. A response of any status is kept
  /// for [responseFor]; a request that could not be sent keeps its reason
  /// for [errorFor].
  Future<void> send(String id, ApiTryItInput input) async {
    final endpoint = _endpoint(id);
    final body = endpoint.bodySkeleton == null
        ? null
        : input.body ?? endpoint.bodySkeleton;
    _inputs[id] = input;
    _sending.add(id);
    _errors.remove(id);
    notifyListeners();
    try {
      final response = await _send(
        method: endpoint.method,
        uri: requestUri(id, input),
        body: body == null || body.trim().isEmpty ? null : body,
      );
      _responses[id] = ApiResponseItem(
        statusCode: response.statusCode,
        headers: response.headers,
        body: response.truncated ? response.body : _pretty(response.body),
        truncated: response.truncated,
      );
    } catch (error) {
      _errors[id] = Errors.message(error, 'send the request');
    }
    _sending.remove(id);
    notifyListeners();
  }

  ApiEndpointItem _endpoint(String id) =>
      _endpoints.firstWhere((endpoint) => endpoint.id == id);
}

Future<List<model.ApiEndpoint>> _loadRegistry() async {
  await registry.loadLibrary();
  return registry.apiEndpoints;
}

/// [endpoint] as the package's widgets take it.
ApiEndpointItem _toItem(model.ApiEndpoint endpoint) {
  final requestSchema = endpoint.requestSchema;
  final takesBody = endpoint.parameters.any(
    (parameter) => parameter.location == model.ApiParameterLocation.body,
  );
  return ApiEndpointItem(
    id: apiEndpointId(endpoint.method, endpoint.path),
    method: endpoint.method,
    path: endpoint.path,
    tag: endpoint.tags.firstOrNull ?? ApiExplorerController.notInSwaggerTag,
    summary: endpoint.summary,
    description: endpoint.description,
    parameters: [
      for (final parameter in endpoint.parameters)
        ApiParameterItem(
          name: parameter.name,
          location: ApiParameterLocation.values.byName(parameter.location.name),
          required: parameter.required,
          type: parameter.type,
          description: parameter.description,
        ),
    ],
    requestSchema: requestSchema == null ? null : _pretty(requestSchema),
    bodySkeleton: requestSchema != null
        ? _encoder.convert(jsonSchemaSample(jsonDecode(requestSchema)))
        : takesBody
        ? '{}'
        : null,
    responses: [
      for (final response in endpoint.responses)
        ApiResponseSchemaItem(
          status: response.status,
          description: response.description,
          schema: response.schema == null ? null : _pretty(response.schema!),
        ),
    ],
    callers: endpoint.callers,
    inSwagger: endpoint.inSwagger,
  );
}

/// The key-safe id of the endpoint [method] [path]: lower case, every run of
/// anything but a letter or digit one `_`, so `GET /api/v0/albums/{id}` is
/// `get_api_v0_albums_id`.
@visibleForTesting
String apiEndpointId(String method, String path) => '$method $path'
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_|_$'), '');

const _encoder = JsonEncoder.withIndent('  ');

/// [text] indented when it is JSON, as it came otherwise.
String _pretty(String text) {
  try {
    return _encoder.convert(jsonDecode(text));
  } on FormatException {
    return text;
  }
}
