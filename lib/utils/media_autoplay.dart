import 'package:quark/utils/media_autoplay_stub.dart'
    if (dart.library.js_interop) 'package:quark/utils/media_autoplay_web.dart';

/// Whether a player may start playback without the user pressing play.
///
/// Always `true` on native platforms. On web it is `true` only once the user
/// has interacted with the page: a tab opened straight onto a video's URL has
/// no gesture behind it, and the browser's autoplay policy rejects play()
/// there.
bool canAutoplayMedia() => canAutoplayMediaPlatform();
