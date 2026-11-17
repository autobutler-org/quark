import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/image_rendition.dart';
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
  showMessage(context, message, duration: const Duration(seconds: 2));
}

/// Whether a photo can be put on the clipboard here (#3436): on web in a
/// secure context. Native builds have no image clipboard yet.
bool get isImageClipboardAvailable =>
    isClipboardAvailable && isImageClipboardAvailablePlatform;

/// Why a photo cannot be copied right now, or null when it can. A disabled
/// Copy entry carries it, and Ctrl/Cmd+C shows it.
String? get imageClipboardUnavailableReason =>
    clipboardUnavailableReason ??
    (isImageClipboardAvailablePlatform
        ? null
        : 'Copying a photo works in the web app for now');

/// Puts a PNG's bytes on the clipboard. The bytes come as a future so a
/// browser can start the write inside the user's gesture.
typedef ClipboardImageWriter = Future<void> Function(Future<Uint8List> png);

/// Copies the photo [loadPhoto] fetches to the clipboard as a PNG no larger
/// than [ClipboardImageConfig.maxDimension] (#3436), and confirms it with
/// "Copied to clipboard" or says why it could not.
///
/// [loadPhoto] returns the photo's displayable bytes, or null when there are
/// none. [writer] defaults to the platform's clipboard, and without it an
/// unavailable clipboard shows [imageClipboardUnavailableReason] instead.
Future<void> copyPhotoToClipboard(
  BuildContext context,
  Future<Uint8List?> Function() loadPhoto, {
  ClipboardImageWriter? writer,
}) async {
  final reason = writer == null ? imageClipboardUnavailableReason : null;
  if (reason != null) {
    showMessage(context, reason);
    return;
  }
  Future<Uint8List> png() async {
    final bytes = await loadPhoto();
    if (bytes == null) throw Exception('The photo has no bytes to copy');
    return pngRendition(bytes);
  }

  try {
    // Started before any await, so the write stays inside the gesture.
    await (writer ?? writeClipboardImagePlatform)(png());
    if (!context.mounted) return;
    showMessage(
      context,
      'Copied to clipboard',
      duration: const Duration(seconds: 2),
    );
  } catch (e) {
    if (context.mounted) {
      showMessage(context, Errors.message(e, 'copy the photo'));
    }
  }
}
