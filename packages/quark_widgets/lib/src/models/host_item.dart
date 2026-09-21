/// One saved Quark, as the drawer names it.
///
/// The caller shortens [address] for display before passing it; the package
/// never parses a URL.
class HostItem {
  /// Creates a host named [name] at [address].
  const HostItem({required this.name, required this.address});

  /// The nickname someone gave this Quark.
  final String name;

  /// Where it lives, already shortened for display, or empty to show none.
  final String address;
}
