import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quark/controllers/api_explorer_controller.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The API explorer (#4077), a drill-down from Settings' About tab: every
/// endpoint of the Quark's API, grouped like the Swagger UI's, each with its
/// parameters and schemas and a "try it" form that sends as the signed-in
/// user. A request that is not a GET is confirmed first, naming its method
/// and URL, because it runs against the user's real data.
///
/// Key prefixes: `api_explorer_page`, `api_explorer_error`,
/// `api_confirm_confirm` and `api_confirm_cancel`, plus those of
/// [ApiEndpointList] and [ApiEndpointDetails].
class ApiExplorerPage extends StatefulWidget {
  /// Creates the page.
  const ApiExplorerPage({this.controller, super.key});

  /// A controller to use instead of the real one; the page disposes it.
  @visibleForTesting
  final ApiExplorerController? controller;

  @override
  State<ApiExplorerPage> createState() => _ApiExplorerPageState();
}

class _ApiExplorerPageState extends State<ApiExplorerPage> {
  late final ApiExplorerController _controller =
      widget.controller ?? ApiExplorerController();

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Sends [input] to [endpoint], once the user has confirmed a request that
  /// can change data.
  Future<void> _send(ApiEndpointItem endpoint, ApiTryItInput input) async {
    if (_controller.needsConfirmation(endpoint.id)) {
      final uri = _controller.requestUri(endpoint.id, input);
      final confirmed = await confirmDestructive(
        context,
        title: 'Send this ${endpoint.method} request?',
        body:
            '${endpoint.method} $uri\n\nIt runs as you, against the real data '
            'on this Quark.',
        keyPrefix: 'api_confirm',
        confirmLabel: 'Send',
        destructive: endpoint.method == 'DELETE',
      );
      if (!confirmed || !mounted) return;
    }
    await _controller.send(endpoint.id, input);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('api_explorer_page'),
      appBar: ChromeAppBar(title: const Text('API Explorer')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final expanded = _controller.expanded;
            final loadError = _controller.loadError;
            if (_controller.isLoading) {
              return const Center(child: QuarkLoader());
            }
            if (loadError != null) {
              return EmptyStateWidget(
                key: const ValueKey('api_explorer_error'),
                icon: QuarkIcons.info_outline,
                headline: loadError,
              );
            }
            return ApiEndpointList(
              endpoints: _controller.visibleEndpoints,
              initialQuery: _controller.query,
              onSearchChanged: _controller.search,
              onToggle: _controller.toggle,
              expandedId: expanded?.id,
              expandedChild: expanded == null
                  ? null
                  : ApiEndpointDetails(
                      key: ValueKey(expanded.id),
                      endpoint: expanded,
                      input: _controller.inputFor(expanded.id),
                      onInputChanged: (input) =>
                          _controller.updateInput(expanded.id, input),
                      onSend: (input) => _send(expanded, input),
                      isSending: _controller.isSending(expanded.id),
                      response: _controller.responseFor(expanded.id),
                      error: _controller.errorFor(expanded.id),
                    ),
            );
          },
        ),
      ),
    );
  }
}
