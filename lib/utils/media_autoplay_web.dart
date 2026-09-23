import 'package:web/web.dart' as web;

/// Web: the browser allows play() only after the user has interacted with
/// the page at least once.
bool canAutoplayMediaPlatform() =>
    web.window.navigator.userActivation.hasBeenActive;
