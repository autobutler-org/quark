import 'package:material_ui/material_ui.dart';

import '../../core/quark_loader.dart';
import '../../core/quark_tint_badge.dart';
import '../../models/api_endpoint_item.dart';
import '../../theme/quark_tokens.dart';
import 'api_code_block.dart';

/// The response panel of `ApiEndpointDetails`: a loader while [isSending],
/// else [error] as given, else [response]'s status, a "Truncated" mark when
/// the caller cut the body short, its headers and its body.
///
/// The status is colored by class from the tokens: 2xx success, 3xx the
/// accent, 4xx warning, 5xx error.
///
/// Key prefixes: `api_response_loader`, `api_response_error`,
/// `api_response_status`, `api_response_truncated`, `api_response_headers`
/// and `api_response_body`.
class ApiResponsePanel extends StatelessWidget {
  /// Creates the panel.
  const ApiResponsePanel({
    this.response,
    this.isSending = false,
    this.error,
    super.key,
  });

  /// The response received, or null before one arrives.
  final ApiResponseItem? response;

  /// Whether a request is in flight. Wins over [error] and [response].
  final bool isSending;

  /// Why the request could not be sent, written by the caller. Wins over
  /// [response].
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;
    final response = this.response;
    if (isSending) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: QuarkLoader(key: ValueKey('api_response_loader'), size: 20),
      );
    }
    if (error != null) {
      return Text(
        error,
        key: const ValueKey('api_response_error'),
        style: TextStyle(color: tokens.error),
      );
    }
    if (response == null) return const SizedBox.shrink();

    final status = response.statusCode;
    final statusColor = switch (status ~/ 100) {
      2 => tokens.success,
      3 => tokens.primary,
      4 => tokens.warning,
      5 => tokens.error,
      _ => tokens.secondaryForeground,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: tokens.spacingSm,
      children: [
        Wrap(
          spacing: tokens.spacingSm,
          runSpacing: tokens.spacingXs,
          children: [
            QuarkTintBadge(
              key: const ValueKey('api_response_status'),
              label: '$status',
              color: statusColor,
              semanticLabel: 'Status $status',
            ),
            if (response.truncated)
              QuarkTintBadge(
                key: const ValueKey('api_response_truncated'),
                label: 'Truncated',
                color: tokens.warning,
                semanticLabel: 'Body truncated',
              ),
          ],
        ),
        if (response.headers.isNotEmpty)
          ApiCodeBlock(
            key: const ValueKey('api_response_headers'),
            text: [
              for (final MapEntry(:key, :value) in response.headers.entries)
                '$key: $value',
            ].join('\n'),
          ),
        ApiCodeBlock(
          key: const ValueKey('api_response_body'),
          text: response.body,
        ),
      ],
    );
  }
}
