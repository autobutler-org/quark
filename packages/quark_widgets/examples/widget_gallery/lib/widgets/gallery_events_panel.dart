import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The bottom panel: the callbacks the current example has fired.
class GalleryEventsPanel extends StatelessWidget {
  /// Creates the panel listing [events], newest first.
  const GalleryEventsPanel({
    required this.events,
    required this.onClear,
    super.key,
  });

  /// The recorded events, newest first.
  final List<String> events;

  /// Called by the clear button, which is disabled while [events] is empty.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return SizedBox(
      height: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.spacingMd,
              tokens.spacingSm,
              tokens.spacingSm,
              0,
            ),
            child: Row(
              children: [
                Text(
                  'Events (${events.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                TextButton(
                  onPressed: events.isEmpty ? null : onClear,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          Expanded(
            child: events.isEmpty
                ? Padding(
                    padding: EdgeInsets.symmetric(horizontal: tokens.spacingMd),
                    child: Text(
                      'Callbacks from the example land here, newest first.',
                      style: TextStyle(
                        color: tokens.mutedForeground,
                        fontSize: 12,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: tokens.spacingMd),
                    itemCount: events.length,
                    itemBuilder: (context, index) => Text(
                      events[index],
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: tokens.secondaryForeground,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
