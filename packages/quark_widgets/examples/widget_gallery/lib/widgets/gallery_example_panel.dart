import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../docs.g.dart';
import '../registry.dart';

/// The middle panel: the selected entry's live example over its class docs.
class GalleryExamplePanel extends StatelessWidget {
  /// Creates the example pane for [entry].
  const GalleryExamplePanel({
    required this.entry,
    required this.onEvent,
    super.key,
  });

  /// The entry to render.
  final GalleryEntry entry;

  /// Passed to the entry's builder as its `log` callback, so every callback
  /// the example fires reaches the event panel.
  final ValueChanged<String> onEvent;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final docs = widgetDocs[entry.name];

    return SingleChildScrollView(
      padding: EdgeInsets.all(tokens.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.name, style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: tokens.spacingLg),
          entry.build(context, onEvent),
          SizedBox(height: tokens.spacingLg),
          const Divider(),
          SizedBox(height: tokens.spacingMd),
          Text('Documentation', style: Theme.of(context).textTheme.titleSmall),
          SizedBox(height: tokens.spacingSm),
          SelectableText(
            docs ??
                'No class documentation found. Add a /// block to the class and '
                    'run `make -C packages/quark_widgets generate/docs`.',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.5,
              color: docs == null
                  ? tokens.mutedForeground
                  : tokens.secondaryForeground,
            ),
          ),
        ],
      ),
    );
  }
}
