import 'package:flutter/material.dart';

import '../../core/quark_loader.dart';
import '../../markdown/quark_markdown_view/markdown_inline_spans.dart';
import '../../models/api_endpoint_item.dart';
import '../../theme/quark_tokens.dart';

/// The "try it" form of `ApiEndpointDetails`: one field per path and query
/// parameter, a multi-line body field when the endpoint takes a body, and a
/// Send button.
///
/// The fields start from [input] and report every edit through [onChanged],
/// so a caller that keeps the values can hand them back after the form is
/// rebuilt. Send hands the values to [onSend] and does nothing else; asking
/// before a request that changes data is the caller's.
///
/// Key prefixes: `api_param_<name>` on each parameter field, `api_body` on
/// the body field, and `api_send` on the Send button.
class ApiTryItForm extends StatefulWidget {
  /// Creates the form for [endpoint].
  const ApiTryItForm({
    required this.endpoint,
    required this.input,
    required this.onSend,
    this.onChanged,
    this.isSending = false,
    super.key,
  });

  /// The endpoint the form sends to.
  final ApiEndpointItem endpoint;

  /// The values the fields start with.
  final ApiTryItInput input;

  /// Called with the form's values when Send is pressed.
  final ValueChanged<ApiTryItInput> onSend;

  /// Called with the form's values after every edit. Null reports nothing.
  final ValueChanged<ApiTryItInput>? onChanged;

  /// Whether a request is in flight, which disables Send.
  final bool isSending;

  @override
  State<ApiTryItForm> createState() => _ApiTryItFormState();
}

class _ApiTryItFormState extends State<ApiTryItForm> {
  late final Map<String, TextEditingController> _parameters = {
    for (final parameter in widget.endpoint.parameters)
      if (parameter.location == ApiParameterLocation.path ||
          parameter.location == ApiParameterLocation.query)
        parameter.name: TextEditingController(
          text: widget.input.parameters[parameter.name] ?? '',
        ),
  };

  late final TextEditingController? _body = widget.endpoint.bodySkeleton == null
      ? null
      : TextEditingController(
          text: widget.input.body ?? widget.endpoint.bodySkeleton,
        );

  ApiTryItInput get _values => ApiTryItInput(
    parameters: {
      for (final MapEntry(:key, :value) in _parameters.entries) key: value.text,
    },
    body: _body?.text,
  );

  void _changed(String _) => widget.onChanged?.call(_values);

  @override
  void dispose() {
    for (final controller in _parameters.values) {
      controller.dispose();
    }
    _body?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final body = _body;
    final required = {
      for (final parameter in widget.endpoint.parameters)
        if (parameter.required) parameter.name,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: tokens.spacingSm,
      children: [
        for (final MapEntry(key: name, value: controller)
            in _parameters.entries)
          TextField(
            key: ValueKey('api_param_$name'),
            controller: controller,
            decoration: InputDecoration(
              labelText: required.contains(name) ? '$name *' : name,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: _changed,
          ),
        if (body != null)
          TextField(
            key: const ValueKey('api_body'),
            controller: body,
            minLines: 4,
            maxLines: 12,
            style: const TextStyle(
              fontFamily: markdownMonoFamily,
              fontFamilyFallback: markdownMonoFallback,
            ),
            decoration: const InputDecoration(
              labelText: 'Body',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            onChanged: _changed,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey('api_send'),
            onPressed: widget.isSending ? null : () => widget.onSend(_values),
            icon: widget.isSending ? const QuarkLoader(size: 16) : null,
            label: const Text('Send'),
          ),
        ),
      ],
    );
  }
}
