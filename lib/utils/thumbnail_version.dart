/// The version of a Quark photo's thumbnail as the thumbnail URL's `v` names
/// it (#4217): the photo's [mtimeSeconds] and its saved [rotationQuarters]
/// joined by a dot, as in `1700000000.1`.
///
/// A URL whose `v` is the current version is served as immutable, so the
/// browser and the native store keep it without asking again. A rotation or a
/// new file changes the version, and with it the URL. Null when the mtime is
/// unknown (0), leaving the URL unversioned and revalidated as before.
String? thumbnailVersion(int mtimeSeconds, int rotationQuarters) =>
    mtimeSeconds > 0 ? '$mtimeSeconds.$rotationQuarters' : null;

/// [url] with `v` set to [version], or [url] itself when [version] is null.
Uri withThumbnailVersion(Uri url, String? version) => version == null
    ? url
    : url.replace(queryParameters: {...url.queryParameters, 'v': version});
