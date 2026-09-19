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

/// Whether [path] on [serial] is an account's home itself, `users/<name>` on
/// the internal drive, rather than something inside it or a `users` folder on
/// a USB drive. The Quark refuses a member's delete or move of one (#2016);
/// this mirrors its `authutil.IsHomeRoot`, so keep the two in step.
bool isHomeRoot(String serial, String path) {
  if (serial.trim().isNotEmpty) return false;
  final segments = path
      .split('/')
      .where((s) => s.isNotEmpty && s != '.')
      .toList();
  return segments.length == 2 && segments.first == 'users';
}
