import 'package:flutter/material.dart';

/// One dependency in a software bill of materials.
class SbomEntry {
  /// Creates an entry for a package.
  const SbomEntry({required this.name, required this.version});

  /// The package name, as the ecosystem spells it.
  final String name;

  /// The resolved version.
  final String version;
}

/// A collapsed list of dependencies, headed by a count.
///
/// Settings shows one of these per ecosystem. Collapsed by default because a
/// bill of materials runs to hundreds of rows and is reference material, not
/// something anyone reads on the way past.
class SbomExpansionTile extends StatelessWidget {
  /// Creates the tile for [items].
  const SbomExpansionTile({
    required this.title,
    required this.subtitle,
    required this.items,
    super.key,
  });

  /// The ecosystem, for instance 'Go dependencies'.
  final String title;

  /// The line under the title, usually a count.
  final String subtitle;

  /// The dependencies, rendered in the order given.
  final List<SbomEntry> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        children: items
            .map(
              (item) => ListTile(
                dense: true,
                title: Text(item.name, style: const TextStyle(fontSize: 13)),
                trailing: Text(
                  item.version,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
