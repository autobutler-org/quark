/// What the Files grouping toggle means, in words (#2037).
///
/// "Unified" and "Per-device" name the modes but explain nothing, and a
/// household owner meeting them for the first time has no way to tell what
/// either will do. Both places that offer the toggle — the wide bar's chip
/// and the compact Views menu — read their explanation from here so they
/// cannot drift apart.
abstract final class ViewGroupingCopy {
  /// What the unified view does.
  static const String unified = 'All your drives shown together';

  /// What the per-device view does.
  static const String perDevice = 'Each drive listed separately';

  /// The explanation for the mode currently on.
  static String forMode({required bool isUnified}) =>
      isUnified ? unified : perDevice;
}
