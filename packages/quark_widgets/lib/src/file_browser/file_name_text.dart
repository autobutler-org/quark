import 'package:material_ui/material_ui.dart';

/// A file or folder name on one line that keeps its extension in view.
///
/// A name that fits is a single [Text]. One that does not is cut short with
/// an ellipsis before the extension, so `Budget 2026 quarterly.qsheet` reads
/// `Budget 2026 qu….qsheet` rather than `Budget 2026 quarte…`, and a phone
/// still says what kind of file it is (#4226). A name with no extension, or
/// one whose "extension" is too long to be one, is cut at the end. A screen
/// reader hears the whole name either way.
///
/// Key prefixes: none; the row it sits in carries the key.
///
/// ```dart
/// FileNameText(node.name, style: theme.textTheme.bodyLarge);
/// ```
class FileNameText extends StatelessWidget {
  /// Creates the text for [name].
  const FileNameText(this.name, {this.style, super.key});

  /// The longest tail, dot included, still treated as an extension.
  static const int maxExtensionLength = 10;

  /// The whole file or folder name.
  final String name;

  /// The style of both runs. Null takes the ambient [DefaultTextStyle].
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final dot = name.lastIndexOf('.');
    final hasExtension =
        dot > 0 &&
        dot < name.length - 1 &&
        name.length - dot <= maxExtensionLength;
    final whole = Text(
      name,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (!hasExtension) return whole;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(
            text: name,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final fits = painter.width <= constraints.maxWidth;
        painter.dispose();
        if (fits) return whole;
        return Semantics(
          label: name,
          excludeSemantics: true,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  name.substring(0, dot),
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(name.substring(dot), style: style, maxLines: 1),
            ],
          ),
        );
      },
    );
  }
}
