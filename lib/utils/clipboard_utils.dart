import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quark/utils/clipboard_utils_stub.dart'
    if (dart.library.js_interop) 'package:quark/utils/clipboard_utils_web.dart';

/// Whether the Clipboard API is available in the current context.
///
/// Returns `true` on native platforms (always available) and on web when
/// running in a secure context (HTTPS or localhost). Returns `false` on
/// plain HTTP web contexts where the browser blocks clipboard access.
bool get isClipboardAvailable => isClipboardAvailablePlatform;

/// Why the clipboard cannot be used right now, or null when it can.
///
/// Hand this to `CopyButton.unavailableReason`: the package renders the
/// sentence, the app writes it.
String? get clipboardUnavailableReason =>
    isClipboardAvailable ? null : 'Clipboard unavailable — use HTTPS to enable';

/// The clipboard's plain text, or null when it holds none.
///
/// On web the browser may ask the user for permission first.
Future<String?> readClipboardText() async =>
    (await Clipboard.getData(Clipboard.kTextPlain))?.text;

/// Replaces the clipboard's text with [text], without a confirmation.
Future<void> writeClipboardText(String text) =>
    Clipboard.setData(ClipboardData(text: text));

/// Copies [text] and confirms it with a snack bar reading [message].
///
/// The clipboard is a platform channel, so it stays app-side; `CopyButton`
/// reaches it through its `onCopy` handler.
Future<void> copyToClipboard(
  BuildContext context,
  String text, {
  String message = 'Copied to clipboard',
}) async {
  await writeClipboardText(text);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}
