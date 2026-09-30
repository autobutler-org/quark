import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

import 'registry.dart';
import 'widgets/gallery_events_panel.dart';
import 'widgets/gallery_example_panel.dart';
import 'widgets/gallery_home.dart';
import 'widgets/gallery_index_panel.dart';
import 'widgets/gallery_theme_panel.dart';

/// How many callback events the bottom panel keeps.
const int _eventLimit = 20;

/// Runs the gallery.
void main() {
  runApp(const WidgetGalleryApp());
}

/// The gallery: every widget in `quark_widgets` rendered with fake data, next
/// to its documentation, over a theme you can edit while it runs.
class WidgetGalleryApp extends StatefulWidget {
  /// Creates the gallery app.
  const WidgetGalleryApp({super.key});

  @override
  State<WidgetGalleryApp> createState() => _WidgetGalleryAppState();
}

class _WidgetGalleryAppState extends State<WidgetGalleryApp> {
  Brightness _brightness = Brightness.dark;
  bool _highContrast = false;
  QuarkTokens _tokens = QuarkTokens.dark;
  GalleryEntry _selected = registry.first;
  String _filter = '';
  final List<String> _events = [];

  void _log(String event) {
    setState(() {
      _events.insert(0, event);
      if (_events.length > _eventLimit) _events.removeLast();
    });
  }

  void _toggleBrightness() {
    setState(() {
      _brightness = _brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark;
      _tokens = _shippedTokens();
    });
  }

  void _toggleHighContrast() {
    setState(() {
      _highContrast = !_highContrast;
      _tokens = _shippedTokens();
    });
  }

  /// The shipped token set for the current brightness and contrast, so each
  /// switch starts from a designed set rather than carrying one set's colors
  /// into another.
  QuarkTokens _shippedTokens() => switch ((_brightness, _highContrast)) {
    (Brightness.dark, false) => QuarkTokens.dark,
    (Brightness.light, false) => QuarkTokens.light,
    (Brightness.dark, true) => QuarkTokens.highContrastDark,
    (Brightness.light, true) => QuarkTokens.highContrastLight,
  };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuarkWidgets Gallery',
      debugShowCheckedModeBanner: false,
      theme: QuarkTheme.from(_tokens, _brightness),
      home: GalleryHome(
        brightness: _brightness,
        onToggleBrightness: _toggleBrightness,
        index: GalleryIndexPanel(
          filter: _filter,
          selected: _selected,
          onFilterChanged: (value) => setState(() => _filter = value),
          onSelected: (entry) => setState(() => _selected = entry),
        ),
        example: GalleryExamplePanel(entry: _selected, onEvent: _log),
        themePanel: GalleryThemePanel(
          tokens: _tokens,
          brightness: _brightness,
          onToggleBrightness: _toggleBrightness,
          highContrast: _highContrast,
          onToggleHighContrast: _toggleHighContrast,
          onTokensChanged: (tokens) => setState(() => _tokens = tokens),
        ),
        events: GalleryEventsPanel(
          events: _events,
          onClear: () => setState(_events.clear),
        ),
      ),
    );
  }
}
