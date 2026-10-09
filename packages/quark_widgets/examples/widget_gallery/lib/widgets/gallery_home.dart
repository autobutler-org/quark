import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The gallery's one screen: three panels side by side over the event log.
class GalleryHome extends StatelessWidget {
  /// Creates the screen around the four panels.
  const GalleryHome({
    required this.brightness,
    required this.onToggleBrightness,
    required this.highContrast,
    required this.onToggleHighContrast,
    required this.index,
    required this.example,
    required this.themePanel,
    required this.events,
    super.key,
  });

  /// The brightness the gallery is showing, driving the app bar icon.
  final Brightness brightness;

  /// Called by the app bar's light/dark button.
  final VoidCallback onToggleBrightness;

  /// Whether the high-contrast tokens are showing, driving the app bar icon.
  final bool highContrast;

  /// Called by the app bar's high-contrast button.
  final VoidCallback onToggleHighContrast;

  /// The left panel, listing the registry.
  final Widget index;

  /// The middle panel, rendering the selected entry.
  final Widget example;

  /// The right panel, editing the theme tokens.
  final Widget themePanel;

  /// The bottom panel, logging the example's callbacks.
  final Widget events;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('QuarkWidgets Gallery'),
        actions: [
          Tooltip(
            message: 'Toggle high contrast',
            child: IconButton(
              key: const ValueKey('gallery_high_contrast_button'),
              isSelected: highContrast,
              icon: const Icon(Icons.contrast),
              onPressed: onToggleHighContrast,
            ),
          ),
          Tooltip(
            message: 'Toggle light and dark',
            child: IconButton(
              icon: Icon(
                brightness == Brightness.dark
                    ? Icons.light_mode
                    : Icons.dark_mode,
              ),
              onPressed: onToggleBrightness,
            ),
          ),
          SizedBox(width: tokens.spacingSm),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Panels take a share of the width rather than a fixed size, so
                // the example area can never be squeezed to a negative width.
                final panel = (constraints.maxWidth * 0.28).clamp(0.0, 300.0);
                return Row(
                  children: [
                    SizedBox(width: panel, child: index),
                    const VerticalDivider(width: 1),
                    Expanded(child: example),
                    const VerticalDivider(width: 1),
                    SizedBox(width: panel, child: themePanel),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          events,
        ],
      ),
    );
  }
}
