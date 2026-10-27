import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Opens the Properties sheet.
///
/// The sheet shows [properties]. [isLoading] and [error] are the load, and
/// [onRetry] is the error's Retry action. The body is
/// [QuarkDocumentProperties], so a count marked `parsed` reads as coming
/// from this preview and a count marked `saved` as the authoring
/// application's last saved value.
Future<void> showDocumentPropertiesSheet(
  BuildContext context, {
  DocumentProperties? properties,
  bool isLoading = false,
  String? error,
  VoidCallback? onRetry,
}) => showQuarkSheet<void>(
  context,
  title: 'Properties',
  builder: (_) => QuarkDocumentProperties(
    properties: properties,
    isLoading: isLoading,
    error: error,
    onRetry: onRetry,
  ),
);
