/// Trims [value] and drops its trailing slashes. This file holds the file browser's path helpers: normalizing,
/// joining, parents, and the home, users and groups roots.
String trimTrailingSlashes(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  return trimmed.replaceFirst(RegExp(r'/+$'), '');
}

String normalizePath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty || trimmed == '/') {
    return '';
  }

  final withLeadingSlash = trimmed.startsWith('/') ? trimmed : '/$trimmed';
  if (withLeadingSlash.endsWith('/') && withLeadingSlash.length > 1) {
    return withLeadingSlash.substring(0, withLeadingSlash.length - 1);
  }
  return withLeadingSlash;
}

String joinPath(String basePath, String segment) {
  final cleanBase = normalizePath(basePath);
  final cleanSegment = segment.trim().replaceAll(RegExp(r'^/+|/+$'), '');

  if (cleanSegment.isEmpty) {
    return cleanBase;
  }

  if (cleanBase.isEmpty) {
    return '/$cleanSegment';
  }

  return '$cleanBase/$cleanSegment';
}

String parentPath(String path) {
  final normalized = normalizePath(path);
  if (normalized.isEmpty) {
    return '';
  }

  final lastSlash = normalized.lastIndexOf('/');
  if (lastSlash <= 0) {
    return '';
  }

  return normalized.substring(0, lastSlash);
}

String toRootDir(String path) {
  final normalized = normalizePath(path);
  if (normalized.isEmpty) {
    return '';
  }

  return normalized.substring(1);
}

String? serialOrNull(String serial) {
  final trimmed = serial.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

/// The segments of [path] on the internal drive, or null on any other drive,
/// with empty and `.` segments dropped the way the Quark cleans a path.
List<String>? _internalSegments(String serial, String path) {
  if (serial.trim().isNotEmpty) return null;
  return path.split('/').where((s) => s.isNotEmpty && s != '.').toList();
}

/// Whether [path] on [serial] is an account's home itself, `users/<name>` on
/// the internal drive, rather than something inside it or a `users` folder on
/// a USB drive. The Quark refuses a member's delete or move of one (#2016);
/// this mirrors its `accessutil.IsHomeRoot`, so keep the two in step.
bool isHomeRoot(String serial, String path) {
  final segments = _internalSegments(serial, path);
  return segments != null && segments.length == 2 && segments.first == 'users';
}

/// Whether [path] on [serial] is the `users` folder on the internal drive that
/// holds every home. A member has no write access to it, so the Quark refuses
/// their delete or move of it the same way it refuses one of a home (#2016).
bool isUsersDir(String serial, String path) {
  final segments = _internalSegments(serial, path);
  return segments != null && segments.length == 1 && segments.first == 'users';
}

/// Whether [path] on [serial] is a group's folder itself, `groups/<name>` on
/// the internal drive, rather than something inside it or a `groups` folder on
/// a USB drive. The Quark refuses a member's delete or move of one (#2016);
/// this mirrors its `accessutil.IsGroupRoot`, so keep the two in step.
bool isGroupRoot(String serial, String path) {
  final segments = _internalSegments(serial, path);
  return segments != null && segments.length == 2 && segments.first == 'groups';
}

/// Whether [path] on [serial] is the `groups` folder on the internal drive
/// that holds every group's folder. Like `users`, a member may not delete or
/// move it, and nobody may share it (#2016).
bool isGroupsDir(String serial, String path) {
  final segments = _internalSegments(serial, path);
  return segments != null && segments.length == 1 && segments.first == 'groups';
}

/// The folder holding every group's folder, in the browser's own spelling.
/// A listing of it shows only the group folders the caller can reach, so it
/// doubles as the account's own list of groups.
const groupsPath = '/groups';

/// An account's own files, `users/<username>`.
///
/// Empty when no username is known — a session recorded before the app kept
/// one — which reads as the real root, the same place the browser opened
/// before homes existed.
String homePath(String? username) {
  final name = username?.trim() ?? '';
  return name.isEmpty ? '' : normalizePath('users/$name');
}

/// Where the file browser opens when the URL names no path (#2139).
///
/// A member's grants are sparse, so the real root holds nothing but the
/// `users` and `groups` scaffolding and their own files sit two clicks down.
/// They land in their home instead. An admin can reach everything, so the
/// root is a real place for them and they keep landing there.
///
/// A path in the URL always wins over this: a deep link or a reload opens
/// what it names.
String landingPath({required bool isAdmin, required String? username}) =>
    isAdmin ? '' : homePath(username);

/// Whether [path] is [rootPath] or something inside it — the test for whether
/// a caller whose reach starts at [rootPath] can open [path].
///
/// An empty [rootPath] is the real root, which contains everything.
bool isWithin(String rootPath, String path) {
  final root = normalizePath(rootPath);
  if (root.isEmpty) {
    return true;
  }
  final target = normalizePath(path);
  return target == root || target.startsWith('$root/');
}
