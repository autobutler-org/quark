import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// The Music page's search box: it reports every edit through [onChanged]
/// and clears itself with its trailing button.
///
/// Keys: `music_search_field` on the field, `music_search_clear` on the
/// clear button.
class MusicSearchField extends StatefulWidget {
  /// Creates the field.
  const MusicSearchField({required this.onChanged, super.key});

  /// Called with the text after every edit, '' once cleared.
  final ValueChanged<String> onChanged;

  @override
  State<MusicSearchField> createState() => _MusicSearchFieldState();
}

class _MusicSearchFieldState extends State<MusicSearchField> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _clear() {
    _text.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: ListenableBuilder(
        listenable: _text,
        builder: (context, _) => TextField(
          key: const ValueKey('music_search_field'),
          controller: _text,
          onChanged: widget.onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search songs, artists, albums',
            prefixIcon: const Icon(QuarkIcons.search),
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: _text.text.isEmpty
                ? null
                : IconButton(
                    key: const ValueKey('music_search_clear'),
                    tooltip: 'Clear search',
                    icon: const Icon(QuarkIcons.close),
                    onPressed: _clear,
                  ),
          ),
        ),
      ),
    );
  }
}
