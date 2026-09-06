/// MIME filter that steers iOS Safari at the Photos library rather than Files.
///
/// `image/*` and `video/*` together open the library with multi-select.
/// Do not add `capture`: that skips the library and opens the camera.
const String kPhotoUploadAccept = 'image/*,video/*';

/// iPhone, iPad, and iPadOS "desktop" Safari (which reports as Macintosh).
///
/// iPadOS 13+ defaults to a Macintosh user agent. Touch points are how we
/// tell an iPad from a Mac — a Mac has none on the screen.
bool isIosPhotoLibraryClient({
  required String userAgent,
  required String platform,
  required int maxTouchPoints,
}) {
  if (userAgent.contains('iPhone') ||
      userAgent.contains('iPad') ||
      userAgent.contains('iPod')) {
    return true;
  }
  return platform == 'MacIntel' && maxTouchPoints > 1;
}
