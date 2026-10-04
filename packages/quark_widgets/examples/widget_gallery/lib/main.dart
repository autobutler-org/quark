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
  QuarkTokens _tokens = QuarkTokens.dark;
  QuarkThemeColor _themeColor = QuarkThemeColor.classic;
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
      // Start each side from the theme color's own token set rather than
      // carrying dark colors into the light theme.
      _tokens = _themeColor.tokensFor(_brightness);
    });
  }

  /// Picking a theme color replaces the whole token set, hand edits included,
  /// the way `QuarkTheme.light` and `QuarkTheme.dark` build from one.
  void _setThemeColor(QuarkThemeColor themeColor) {
    setState(() {
      _themeColor = themeColor;
      _tokens = themeColor.tokensFor(_brightness);
    });
  }

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
          themeColor: _themeColor,
          onToggleBrightness: _toggleBrightness,
          onThemeColorChanged: _setThemeColor,
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
