import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The fake album sidebar the layout examples put in a pane.
///
/// Shrink-wrapped on purpose: the collapsed layout hands its sidebar unbounded
/// height, where an [Expanded] is a hard layout error (#1599).
class DemoAlbumSidebar extends StatelessWidget {
  /// Creates the fake sidebar.
  const DemoAlbumSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return Padding(
      padding: EdgeInsets.all(tokens.spacingMd),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Albums', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: tokens.spacingSm),
          for (final album in const ['Trips', 'Iceland', 'Japan'])
            Padding(
              padding: EdgeInsets.only(bottom: tokens.spacingXs),
              child: Text(
                album,
                style: TextStyle(color: tokens.secondaryForeground),
              ),
            ),
        ],
      ),
    );
  }
}
