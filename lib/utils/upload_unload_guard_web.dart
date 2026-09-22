import 'dart:js_interop';

import 'package:web/web.dart' as web;

web.EventListener? _listener;

/// Asks the browser to confirm before leaving the page while [active] is true, so an in-progress upload is not
/// lost to a closed tab.
void setUploadUnloadGuardPlatform({required bool active}) {
  if (active) {
    if (_listener != null) {
      return;
    }
    // Browsers ignore any custom message here and show their own wording, so
    // preventDefault is the whole contract — the text is not ours to choose.
    final listener = ((web.Event event) => event.preventDefault()).toJS;
    _listener = listener;
    web.window.addEventListener('beforeunload', listener);
    return;
  }

  final listener = _listener;
  if (listener == null) {
    return;
  }
  web.window.removeEventListener('beforeunload', listener);
  _listener = null;
}
