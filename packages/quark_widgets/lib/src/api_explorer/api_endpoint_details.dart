import 'package:flutter/material.dart';

import '../layout/quark_section.dart';
import '../markdown/quark_markdown_view/markdown_inline_spans.dart';
import '../models/api_endpoint_item.dart';
import '../theme/quark_tokens.dart';
import 'api_endpoint_details/api_code_block.dart';
import 'api_endpoint_details/api_response_panel.dart';
import 'api_endpoint_details/api_try_it_form.dart';

/// What an expanded row of `ApiEndpointList` shows: the endpoint's
/// description, the client methods that call it, its parameters, request and
/// response schemas, a "try it" form, and the last response.
///
/// Sending is the caller's. Send reports the form's values through [onSend];
/// the caller asks before a request that changes data, sends it, and passes
/// back [isSending], then [response] or [error]. Error copy is the caller's
/// and is rendered as given. The form's values start from [input] and every
/// edit is reported through [onInputChanged], so a caller that keeps them can
/// restore the form after the row scrolls away.
///
/// Key prefixes: `api_param_<name>` on each parameter field, `api_body` on
/// the body field, `api_send` on the Send button, `api_response_loader`,
/// `api_response_error`, `api_response_status`, `api_response_truncated`,
/// `api_response_headers` and `api_response_body` on the response, and
/// `section_<title>` on each section (see `QuarkSection.slug`).
///
/// ```dart
/// ApiEndpointDetails(
///   key: ValueKey(endpoint.id),
///   endpoint: endpoint,
///   input: controller.input,
///   onInputChanged: controller.updateInput,
///   onSend: confirmAndSend,
///   isSending: controller.isSending,
///   response: controller.response,
///   error: controller.sendError,
/// );
/// ```
class ApiEndpointDetails extends StatelessWidget {
  /// Creates the details of [endpoint].
  const ApiEndpointDetails({
    required this.endpoint,
    required this.onSend,
    this.input = const ApiTryItInput(),
    this.onInputChanged,
    this.isSending = false,
    this.response,
    this.error,
    super.key,
  });

  /// The endpoint shown.
  final ApiEndpointItem endpoint;

  /// Called with the form's values when Send is pressed.
  final ValueChanged<ApiTryItInput> onSend;

  /// The values the "try it" form starts with. Read when the form is first
  /// built for [endpoint]; later edits stay in the form.
  final ApiTryItInput input;

  /// Called with the form's values after every edit. Null reports nothing.
  final ValueChanged<ApiTryItInput>? onInputChanged;

  /// Whether a request is in flight: shows a loader and disables Send.
  final bool isSending;

  /// The last response received, or null.
  final ApiResponseItem? response;

  /// Why the last request could not be sent, written by the caller.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: tokens.secondaryForeground,
    );
    final mono = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: markdownMonoFamily,
      fontFamilyFallback: markdownMonoFallback,
    );
    final requestSchema = endpoint.requestSchema;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: tokens.spacingMd,
      children: [
        if (endpoint.description.isNotEmpty) Text(endpoint.description),
        if (endpoint.callers.isNotEmpty)
          QuarkSection(
            title: 'Called by',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final caller in endpoint.callers)
                  Text(caller, style: mono),
              ],
            ),
          ),
        if (endpoint.parameters.isNotEmpty)
          QuarkSection(
            title: 'Parameters',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: tokens.spacingSm,
              children: [
                for (final parameter in endpoint.parameters)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: parameter.name,
                              style: mono?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (parameter.required)
                              TextSpan(
                                text: '  required',
                                style: muted?.copyWith(color: tokens.error),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        [
                          parameter.location.name,
                          if (parameter.type.isNotEmpty) parameter.type,
                        ].join(' · '),
                        style: muted,
                      ),
                      if (parameter.description.isNotEmpty)
                        Text(parameter.description),
                    ],
                  ),
              ],
            ),
          ),
        if (requestSchema != null)
          QuarkSection(
            title: 'Request body',
            child: ApiCodeBlock(text: requestSchema),
          ),
        if (endpoint.responses.isNotEmpty)
          QuarkSection(
            title: 'Responses',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: tokens.spacingSm,
              children: [
                for (final schema in endpoint.responses) ...[
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: schema.status,
                          style: mono?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (schema.description.isNotEmpty)
                          TextSpan(text: '  ${schema.description}'),
                      ],
                    ),
                  ),
                  if (schema.schema case final text?) ApiCodeBlock(text: text),
                ],
              ],
            ),
          ),
        QuarkSection(
          title: 'Try it',
          child: ApiTryItForm(
            key: ValueKey('api_try_it_${endpoint.id}'),
            endpoint: endpoint,
            input: input,
            onChanged: onInputChanged,
            onSend: onSend,
            isSending: isSending,
          ),
        ),
        if (isSending || error != null || response != null)
          QuarkSection(
            title: 'Response',
            child: ApiResponsePanel(
              response: response,
              isSending: isSending,
              error: error,
            ),
          ),
      ],
    );
  }
}
