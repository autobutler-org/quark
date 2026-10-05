/// Which of a `SlideTheme`'s text styles a `TextBox` takes its unset run
/// styles from: its font, size and color.
///
/// A layout's title placeholder is [title], a subtitle [subtitle], and
/// everything else — content placeholders and every ordinary text box —
/// [body]. In `.qslide` it is a text box's `textRole`, left out for
/// [body]; a value this version does not know reads as [body].
enum ThemeTextRole {
  /// A slide title, in the heading font.
  title,

  /// A subtitle under a title.
  subtitle,

  /// Body text.
  body;

  /// The English name a screen reader announces a placeholder by.
  String get label => switch (this) {
        title => 'Title',
        subtitle => 'Subtitle',
        body => 'Content',
      };
}
