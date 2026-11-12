import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/api_explorer_controller.dart';
import 'package:quark/generated/api_explorer_registry.g.dart';
import 'package:quark/models/api_endpoint.dart' as model;
import 'package:quark/services/api_explorer_service.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The API explorer page's state (#4077).
void main() {
  const createItem = model.ApiEndpoint(
    method: 'POST',
    path: '/api/v0/albums/{id}/items',
    inSwagger: true,
    tags: ['albums', 'photos'],
    summary: 'Add photos to an album',
    parameters: [
      model.ApiParameter(
        name: 'id',
        location: model.ApiParameterLocation.path,
        required: true,
        type: 'integer',
      ),
      model.ApiParameter(
        name: 'serial',
        location: model.ApiParameterLocation.query,
        type: 'string',
      ),
      model.ApiParameter(
        name: 'body',
        location: model.ApiParameterLocation.body,
        type: 'object',
      ),
    ],
    requestSchema:
        '{"type":"object","properties":{"paths":{"type":"array",'
        '"items":{"type":"string"}}}}',
    responses: [model.ApiResponse(status: '200', schema: '{"type":"object"}')],
    callers: ['AlbumService.addItems'],
  );
  const health = model.ApiEndpoint(
    method: 'GET',
    path: '/api/v0/health',
    inSwagger: true,
    tags: ['health'],
    summary: 'Device metrics',
  );
  const untagged = model.ApiEndpoint(
    method: 'GET',
    path: '/api/v0/secret',
    inSwagger: false,
    callers: ['SecretService.read'],
  );
  const access = model.ApiEndpoint(
    method: 'GET',
    path: '/api/v0/access',
    inSwagger: true,
    tags: ['access'],
  );

  final sent = <({String method, Uri uri, String? body})>[];
  ApiExplorerResponse answer = (
    statusCode: 200,
    headers: const {},
    body: '',
    truncated: false,
  );
  Object? failure;

  Future<ApiExplorerController> loaded() async {
    final controller = ApiExplorerController(
      loadEndpoints: () async => [untagged, createItem, health, access],
      send: ({required method, required uri, body}) async {
        sent.add((method: method, uri: uri, body: body));
        if (failure != null) throw failure!;
        return answer;
      },
    );
    await controller.load();
    return controller;
  }

  setUp(() {
    sent.clear();
    failure = null;
    answer = (statusCode: 200, headers: const {}, body: '', truncated: false);
  });

  test('maps each endpoint into the package item', () async {
    final controller = await loaded();
    final item = controller.visibleEndpoints.firstWhere(
      (e) => e.method == 'POST',
    );

    expect(controller.isLoading, isFalse);
    expect(item.id, 'post_api_v0_albums_id_items');
    expect(item.tag, 'albums', reason: 'the first Swagger tag groups it');
    expect(item.parameters.map((p) => p.location), [
      ApiParameterLocation.path,
      ApiParameterLocation.query,
      ApiParameterLocation.body,
    ]);
    expect(item.requestSchema, contains('\n  "type": "object"'));
    expect(jsonDecode(item.bodySkeleton!), {
      'paths': [''],
    });
    expect(item.responses.single.schema, '{\n  "type": "object"\n}');
    expect(item.callers, ['AlbumService.addItems']);
  });

  test('groups by tag, the endpoints not in Swagger last', () async {
    final controller = await loaded();

    expect(controller.visibleEndpoints.map((e) => (e.tag, e.inSwagger)), [
      ('access', true),
      ('albums', true),
      ('health', true),
      (ApiExplorerController.notInSwaggerTag, false),
    ]);
  });

  test('a GET with no body parameter has no body field', () async {
    final controller = await loaded();

    expect(
      controller.visibleEndpoints
          .firstWhere((e) => e.path == '/api/v0/health')
          .bodySkeleton,
      isNull,
    );
  });

  test('every endpoint in the registry has a distinct key-safe id', () {
    final ids = [
      for (final endpoint in apiEndpoints)
        apiEndpointId(endpoint.method, endpoint.path),
    ];

    expect(ids.toSet(), hasLength(ids.length));
    expect(ids.where((id) => !RegExp(r'^[a-z0-9_]+$').hasMatch(id)), isEmpty);
  });

  test('a failed load says why', () async {
    final controller = ApiExplorerController(
      loadEndpoints: () async => throw StateError('no registry'),
    );

    await controller.load();

    expect(controller.isLoading, isFalse);
    expect(
      controller.loadError,
      Errors.message(StateError(''), 'load the list of endpoints'),
    );
  });

  test('searches method, path, summary, tags and callers', () async {
    final controller = await loaded();
    List<String> paths() =>
        controller.visibleEndpoints.map((e) => e.path).toList();

    controller.search('post albums');
    expect(paths(), ['/api/v0/albums/{id}/items']);

    controller.search('photos');
    expect(paths(), ['/api/v0/albums/{id}/items'], reason: 'second tag');

    controller.search('SecretService');
    expect(paths(), ['/api/v0/secret']);

    controller.search('METRICS');
    expect(paths(), ['/api/v0/health']);

    controller.search('nothing matches');
    expect(paths(), isEmpty);

    controller.search('  ');
    expect(paths(), hasLength(4));
  });

  test('toggles one endpoint open at a time', () async {
    final controller = await loaded();

    controller.toggle('get_api_v0_health');
    expect(controller.expanded?.path, '/api/v0/health');

    controller.toggle('get_api_v0_access');
    expect(controller.expandedId, 'get_api_v0_access');

    controller.toggle('get_api_v0_access');
    expect(controller.expanded, isNull);
  });

  test('keeps each endpoint form after its row collapses', () async {
    final controller = await loaded();
    const typed = ApiTryItInput(parameters: {'id': '7'}, body: '{}');

    controller.toggle('post_api_v0_albums_id_items');
    controller.updateInput('post_api_v0_albums_id_items', typed);
    controller.toggle('get_api_v0_health');

    expect(controller.inputFor('post_api_v0_albums_id_items'), same(typed));
    expect(controller.inputFor('get_api_v0_health').parameters, isEmpty);
  });

  test('only a GET goes without confirmation', () async {
    final controller = await loaded();

    expect(controller.needsConfirmation('get_api_v0_health'), isFalse);
    expect(controller.needsConfirmation('post_api_v0_albums_id_items'), isTrue);
  });

  test('sends the form as the URL and the body', () async {
    final controller = await loaded();
    answer = (
      statusCode: 200,
      headers: const {'content-type': 'application/json'},
      body: '{"ok":true}',
      truncated: false,
    );

    await controller.send(
      'post_api_v0_albums_id_items',
      const ApiTryItInput(parameters: {'id': '7', 'serial': ''}),
    );

    final request = sent.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/v0/albums/7/items');
    expect(request.uri.hasQuery, isFalse, reason: 'empty query is left out');
    expect(jsonDecode(request.body!), {
      'paths': [''],
    }, reason: 'an untouched body sends the skeleton');
    final response = controller.responseFor('post_api_v0_albums_id_items')!;
    expect(response.statusCode, 200);
    expect(response.body, '{\n  "ok": true\n}');
    expect(response.headers['content-type'], 'application/json');
    expect(controller.isSending('post_api_v0_albums_id_items'), isFalse);
    expect(controller.errorFor('post_api_v0_albums_id_items'), isNull);
  });

  test('shows an error status as a response, not an error', () async {
    final controller = await loaded();
    answer = (
      statusCode: 403,
      headers: const {},
      body: '{"error":"admins only"}',
      truncated: false,
    );

    await controller.send('get_api_v0_health', const ApiTryItInput());

    expect(sent.single.body, isNull, reason: 'a GET sends no body');
    expect(controller.responseFor('get_api_v0_health')?.statusCode, 403);
    expect(controller.errorFor('get_api_v0_health'), isNull);
  });

  test('keeps a truncated body as it came', () async {
    final controller = await loaded();
    answer = (
      statusCode: 200,
      headers: const {},
      body: '{"a":',
      truncated: true,
    );

    await controller.send('get_api_v0_health', const ApiTryItInput());

    final response = controller.responseFor('get_api_v0_health')!;
    expect(response.body, '{"a":');
    expect(response.truncated, isTrue);
  });

  test('a request that could not be sent says why', () async {
    final controller = await loaded();
    failure = const UnauthorizedException();

    await controller.send('get_api_v0_health', const ApiTryItInput());

    expect(
      controller.errorFor('get_api_v0_health'),
      Errors.message(const UnauthorizedException(), 'send the request'),
    );
    expect(controller.responseFor('get_api_v0_health'), isNull);
    expect(controller.isSending('get_api_v0_health'), isFalse);
  });

  test('is sending while the request is in flight', () async {
    final controller = await loaded();
    final pending = controller.send('get_api_v0_health', const ApiTryItInput());

    expect(controller.isSending('get_api_v0_health'), isTrue);
    await pending;
    expect(controller.isSending('get_api_v0_health'), isFalse);
  });
}
