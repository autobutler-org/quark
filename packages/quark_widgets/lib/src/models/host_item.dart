/// One Quark, by name and address: a saved one as the drawer names it, or one
/// found on the local network.
///
/// The caller shapes [address] for display before passing it; the package
/// never parses a URL.
class HostItem {
  /// Creates a host named [name] at [address].
  const HostItem({required this.name, required this.address});

  /// The nickname someone gave this Quark, or the name it announces itself
  /// by on the network.
  final String name;

  /// Where it lives, already shortened for display, or empty to show none.
  final String address;
}
