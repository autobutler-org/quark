import 'package:quark_icons/quark_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const IconGalleryApp());
}

class IconGalleryApp extends StatelessWidget {
  const IconGalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuarkIcons Gallery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const IconGalleryPage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Icon catalogue — add new icons here as you add SVGs to svgs/
// ---------------------------------------------------------------------------

class _IconEntry {
  const _IconEntry(this.data, this.name);
  final IconData data;
  final String name;
}

const _sections = <({String title, List<_IconEntry> icons})>[
  (
    title: 'Row operations',
    icons: [
      _IconEntry(QuarkIcons.insert_row_above, 'insert_row_above'),
      _IconEntry(QuarkIcons.insert_row_below, 'insert_row_below'),
      _IconEntry(QuarkIcons.delete_row, 'delete_row'),
      _IconEntry(QuarkIcons.duplicate_row, 'duplicate_row'),
      _IconEntry(QuarkIcons.clear_row, 'clear_row'),
    ],
  ),
  (
    title: 'Column operations',
    icons: [
      _IconEntry(QuarkIcons.insert_column_left, 'insert_column_left'),
      _IconEntry(QuarkIcons.insert_column_right, 'insert_column_right'),
      _IconEntry(QuarkIcons.delete_column, 'delete_column'),
      _IconEntry(QuarkIcons.duplicate_column, 'duplicate_column'),
      _IconEntry(QuarkIcons.clear_column, 'clear_column'),
    ],
  ),
  (
    title: 'Material aliases (edit actions)',
    icons: [
      _IconEntry(QuarkIcons.undo, 'undo'),
      _IconEntry(QuarkIcons.redo, 'redo'),
      _IconEntry(QuarkIcons.fill_down, 'fill_down'),
      _IconEntry(QuarkIcons.fill_right, 'fill_right'),
    ],
  ),
  (
    title: 'Material aliases (append)',
    icons: [],
  ),
  (
    title: 'Material aliases (data ops)',
    icons: [
      _IconEntry(QuarkIcons.sort, 'sort'),
      _IconEntry(QuarkIcons.remove_duplicates, 'remove_duplicates'),
      _IconEntry(QuarkIcons.find_replace, 'find_replace'),
      _IconEntry(QuarkIcons.go_to_cell, 'go_to_cell'),
    ],
  ),
  (
    title: 'Material aliases (import / export)',
    icons: [
      _IconEntry(QuarkIcons.export_csv, 'export_csv'),
      _IconEntry(QuarkIcons.import_csv, 'import_csv'),
      _IconEntry(QuarkIcons.import_file, 'import_file'),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Gallery page
// ---------------------------------------------------------------------------

class IconGalleryPage extends StatefulWidget {
  const IconGalleryPage({super.key});

  @override
  State<IconGalleryPage> createState() => _IconGalleryPageState();
}

class _IconGalleryPageState extends State<IconGalleryPage> {
  double _iconSize = 40;
  bool _darkMode = false;
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _sections
        .map((s) {
          final icons = s.icons
              .where(
                (e) =>
                    _filter.isEmpty || e.name.contains(_filter.toLowerCase()),
              )
              .toList();
          return (title: s.title, icons: icons);
        })
        .where((s) => s.icons.isNotEmpty)
        .toList();

    return Theme(
      data: _darkMode
          ? ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF1A73E8),
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
            )
          : ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF1A73E8),
              ),
              useMaterial3: true,
            ),
      child: Builder(
        builder: (context) {
          final cs = Theme.of(context).colorScheme;
          return Scaffold(
            appBar: AppBar(
              title: const Text('QuarkIcons Gallery'),
              actions: [
                Tooltip(
                  message: 'Toggle dark mode',
                  child: IconButton(
                    icon: Icon(_darkMode ? Icons.light_mode : Icons.dark_mode),
                    onPressed: () => setState(() => _darkMode = !_darkMode),
                  ),
                ),
              ],
            ),
            body: Column(
              children: [
                // ── Controls bar ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Filter icons…',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                          ),
                          onChanged: (v) => setState(() => _filter = v.trim()),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text('Size: ${_iconSize.round()}'),
                      SizedBox(
                        width: 180,
                        child: Slider(
                          value: _iconSize,
                          min: 16,
                          max: 96,
                          divisions: 10,
                          label: _iconSize.round().toString(),
                          onChanged: (v) => setState(() => _iconSize = v),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // ── Icon grid ─────────────────────────────────────────────
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No icons match "$_filter"',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: filtered.length,
                          itemBuilder: (context, si) {
                            final section = filtered[si];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    20,
                                    16,
                                    8,
                                  ),
                                  child: Text(
                                    section.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          color: cs.primary,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.8,
                                        ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: section.icons
                                        .map(
                                          (e) => _IconTile(
                                            entry: e,
                                            size: _iconSize,
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Icon tile — shows icon + name, tap to copy name
// ---------------------------------------------------------------------------

class _IconTile extends StatefulWidget {
  const _IconTile({required this.entry, required this.size});
  final _IconEntry entry;
  final double size;

  @override
  State<_IconTile> createState() => _IconTileState();
}

class _IconTileState extends State<_IconTile> {
  bool _copied = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.entry.name));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tileSize = widget.size + 64.0;

    return Tooltip(
      message: 'Tap to copy: QuarkIcons.${widget.entry.name}',
      child: InkWell(
        onTap: _copy,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: tileSize,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            border: Border.all(color: _copied ? cs.primary : cs.outlineVariant),
            borderRadius: BorderRadius.circular(12),
            color: _copied ? cs.primaryContainer : cs.surfaceContainerLow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.entry.data,
                size: widget.size,
                color: _copied ? cs.primary : cs.onSurface,
              ),
              const SizedBox(height: 8),
              Text(
                _copied ? '✓ copied' : widget.entry.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: _copied ? cs.primary : cs.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
