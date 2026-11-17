import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web — check window.isSecureContext to determine clipboard availability.
bool get isClipboardAvailablePlatform => web.window.isSecureContext;

/// Web — the async Clipboard API takes images through `ClipboardItem`, which
/// only a secure context exposes.
bool get isImageClipboardAvailablePlatform =>
    web.window.isSecureContext &&
    web.window.has('ClipboardItem') &&
    web.window.navigator.has('clipboard');

/// Web — writes [png] to the clipboard as an `image/png` item.
///
/// The item is handed a promise of the bytes rather than the bytes, so the
/// write starts inside the user's gesture while the photo is still loading:
/// Safari refuses a clipboard write that begins after an `await`.
Future<void> writeClipboardImagePlatform(Future<Uint8List> png) {
  final blob = png.then(
    (bytes) =>
        web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'image/png')),
  );
  final items = JSObject()..setProperty('image/png'.toJS, blob.toJS);
  return web.window.navigator.clipboard
      .write([web.ClipboardItem(items)].toJS)
      .toDart;
}
