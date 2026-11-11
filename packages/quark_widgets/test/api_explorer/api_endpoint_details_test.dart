/// `ApiEndpointDetails` shows an endpoint's parameters, schemas and callers,
/// a "try it" form that reports what was typed, and the response the caller
/// passes back. Its form and response panel are parts, tested through it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _endpoint = ApiEndpointItem(
  id: 'put_files_path',
  method: 'PUT',
  path: '/api/v0/files/{path}',
  tag: 'files',
  description: 'Replaces the file at path.',
  parameters: [
    ApiParameterItem(
      name: 'path',
      location: ApiParameterLocation.path,
      required: true,
      type: 'string',
      description: 'The file, relative to the files root.',
    ),
    ApiParameterItem(
      name: 'serial',
      location: ApiParameterLocation.query,
      type: 'string',
    ),
    ApiParameterItem(name: 'X-Trace', location: ApiParameterLocation.header),
  ],
  requestSchema: '{"name": "string"}',
  bodySkeleton: '{"name": ""}',
  responses: [
    ApiResponseSchemaItem(
      status: '200',
      description: 'Saved',
      schema: '{"ok": "boolean"}',
    ),
  ],
  callers: ['FilesService.save'],
);

void main() {
  ApiEndpointDetails details({
    ApiEndpointItem endpoint = _endpoint,
    ApiTryItInput input = const ApiTryItInput(),
    bool isSending = false,
    ApiResponseItem? response,
    String? error,
    List<ApiTryItInput>? sent,
    List<ApiTryItInput>? changed,
  }) => ApiEndpointDetails(
    endpoint: endpoint,
    input: input,
    isSending: isSending,
    response: response,
    error: error,
    onSend: (value) => sent?.add(value),
    onInputChanged: changed?.add,
  );

  Widget scrolled(Widget child) =>
      SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

  testBothViewports(
    'renders the description, callers, parameters and schemas',
    (tester, size) async {
      await pumpAt(tester, scrolled(details()), size: size);

      expect(tester.takeException(), isNull);
      expect(find.text('Replaces the file at path.'), findsOneWidget);
      expect(find.text('FilesService.save'), findsOneWidget);
      expect(find.text('path  required', findRichText: true), findsOneWidget);
      expect(find.text('header'), findsOneWidget);
      expect(find.text('{"name": "string"}'), findsOneWidget);
      expect(find.text('200  Saved', findRichText: true), findsOneWidget);
      expect(find.text('{"ok": "boolean"}'), findsOneWidget);
      // No response yet, so no response section.
      expect(find.byKey(const ValueKey('section_response')), findsNothing);
    },
  );

  testWidgets('offers a field per path and query parameter, and the body', (
    tester,
  ) async {
    await pumpAt(
      tester,
      scrolled(
        details(input: const ApiTryItInput(parameters: {'path': 'a.txt'})),
      ),
    );

    expect(find.byKey(const ValueKey('api_param_path')), findsOneWidget);
    expect(find.byKey(const ValueKey('api_param_serial')), findsOneWidget);
    expect(find.byKey(const ValueKey('api_param_X-Trace')), findsNothing);
    expect(find.text('a.txt'), findsOneWidget);
    // An untouched body starts from the skeleton.
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('api_body')))
          .controller!
          .text,
      '{"name": ""}',
    );
  });

  testWidgets('hides the body field when the endpoint takes none', (
    tester,
  ) async {
    await pumpAt(
      tester,
      scrolled(
        details(
          endpoint: const ApiEndpointItem(
            id: 'get',
            method: 'GET',
            path: '/x',
            tag: 't',
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('api_body')), findsNothing);
    expect(find.byKey(const ValueKey('api_send')), findsOneWidget);
  });

  testWidgets('reports every edit and sends what was typed', (tester) async {
    final sent = <ApiTryItInput>[];
    final changed = <ApiTryItInput>[];
    await pumpAt(tester, scrolled(details(sent: sent, changed: changed)));

    await tester.enterText(
      find.byKey(const ValueKey('api_param_path')),
      'b.txt',
    );
    await tester.enterText(find.byKey(const ValueKey('api_body')), '{}');
    await tester.ensureVisible(find.byKey(const ValueKey('api_send')));
    await tester.tap(find.byKey(const ValueKey('api_send')));
    await tester.pump();

    expect(changed, hasLength(2));
    expect(changed.last.parameters, {'path': 'b.txt', 'serial': ''});
    expect(sent, hasLength(1));
    expect(sent.single.parameters, {'path': 'b.txt', 'serial': ''});
    expect(sent.single.body, '{}');
  });

  testWidgets('shows a loader and disables Send while sending', (tester) async {
    await pumpAt(tester, scrolled(details(isSending: true)));

    expect(find.byKey(const ValueKey('api_response_loader')), findsOneWidget);
    final send = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('api_send')),
    );
    expect(send.onPressed, isNull);
    expect(find.byKey(const ValueKey('api_response_status')), findsNothing);
  });

  testWidgets('renders the error it is handed', (tester) async {
    await pumpAt(
      tester,
      scrolled(
        details(
          error: "Couldn't reach the Quark.",
          response: const ApiResponseItem(statusCode: 200),
        ),
      ),
    );

    expect(find.text("Couldn't reach the Quark."), findsOneWidget);
    expect(find.byKey(const ValueKey('api_response_status')), findsNothing);
  });

  testBothViewports('renders the status, headers, body and truncated mark', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      scrolled(
        details(
          response: ApiResponseItem(
            statusCode: 403,
            headers: const {'content-type': 'application/json'},
            body: '{"error": "forbidden", "detail": "${'x' * 400}"}',
            truncated: true,
          ),
        ),
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('api_response_loader')), findsNothing);
    expect(find.text('403'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('api_response_truncated')),
      findsOneWidget,
    );
    expect(find.text('content-type: application/json'), findsOneWidget);
    expect(find.byKey(const ValueKey('api_response_body')), findsOneWidget);
    expect(
      tester
          .widget<QuarkTintBadge>(
            find.byKey(const ValueKey('api_response_status')),
          )
          .color,
      QuarkTokens.dark.warning,
    );
  });

  testWidgets('leaves the truncated mark off a whole body', (tester) async {
    await pumpAt(
      tester,
      scrolled(details(response: const ApiResponseItem(statusCode: 204))),
    );
    expect(find.text('204'), findsOneWidget);
    expect(find.byKey(const ValueKey('api_response_truncated')), findsNothing);
    expect(find.byKey(const ValueKey('api_response_headers')), findsNothing);
  });

  testBothViewports('meets the tap target guidelines', (tester, size) async {
    await pumpAt(
      tester,
      scrolled(details(response: const ApiResponseItem(statusCode: 200))),
      size: size,
    );
    await expectTapTargetGuidelines(tester);
  });
}
