import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';

/// Password strength, from weakest to strongest.
enum PasswordStrength {
  /// No password typed yet. The bar is empty and unlabeled.
  empty,

  /// Short, or made of one character class.
  weak,

  /// Long enough, or mixed, but not both.
  fair,

  /// Long and mixed.
  strong,

  /// Long and mixed across every class this scorer looks at.
  veryStrong,
}

/// How a [PasswordStrength] is shown: its label, its color, and how much of
/// the bar it fills.
extension PasswordStrengthDisplay on PasswordStrength {
  /// The word under the bar. Empty for [PasswordStrength.empty], which hides
  /// the label entirely.
  String get label => switch (this) {
    PasswordStrength.empty => '',
    PasswordStrength.weak => 'Weak',
    PasswordStrength.fair => 'Fair',
    PasswordStrength.strong => 'Strong',
    PasswordStrength.veryStrong => 'Very strong',
  };

  /// The bar and label color for this level, drawn from [tokens] so the
  /// gradient follows the theme rather than a hardcoded ramp.
  Color color(QuarkTokens tokens) => switch (this) {
    PasswordStrength.empty => tokens.border,
    PasswordStrength.weak => tokens.error,
    PasswordStrength.fair => tokens.warning,
    PasswordStrength.strong => tokens.success,
    PasswordStrength.veryStrong => tokens.success,
  };

  /// How much of the bar this level fills, from 0 to 1.
  double get fraction => switch (this) {
    PasswordStrength.empty => 0.0,
    PasswordStrength.weak => 0.25,
    PasswordStrength.fair => 0.5,
    PasswordStrength.strong => 0.75,
    PasswordStrength.veryStrong => 1.0,
  };
}

/// Scores [password] into a [PasswordStrength].
///
/// One point each for: eight characters, twelve characters, both cases, a
/// digit, a special character. Score 0 or 1 is weak, 2 fair, 3 strong, 4 or
/// more very strong. An empty password is [PasswordStrength.empty].
PasswordStrength scorePassword(String password) {
  if (password.isEmpty) return PasswordStrength.empty;

  var score = 0;
  if (password.length >= 8) {
    score++;
  }
  if (password.length >= 12) {
    score++;
  }
  if (password.contains(RegExp(r'[A-Z]')) &&
      password.contains(RegExp(r'[a-z]'))) {
    score++;
  }
  if (password.contains(RegExp(r'\d'))) {
    score++;
  }
  if (password.contains(RegExp(r'[^A-Za-z\d]'))) {
    score++;
  }

  return switch (score) {
    0 || 1 => PasswordStrength.weak,
    2 => PasswordStrength.fair,
    3 => PasswordStrength.strong,
    _ => PasswordStrength.veryStrong,
  };
}

/// An animated bar showing how strong [password] is, with the level named
/// underneath.
///
/// Place it beneath a password field. It is advisory only and never blocks a
/// form: validation stays with the field.
///
/// Under reduced motion, when either `MediaQuery.disableAnimationsOf` or the
/// platform's `accessibilityFeatures.reduceMotion` (iOS Reduce Motion) is set,
/// the fill jumps straight to the new level instead of sliding.
///
/// Emits no `ValueKey`s; it is not interactive.
///
/// ```dart
/// PasswordStrengthBar(password: passwordController.text);
/// ```
class PasswordStrengthBar extends StatefulWidget {
  /// Creates a bar reflecting the strength of [password].
  const PasswordStrengthBar({required this.password, super.key});

  /// The password to score. Scored on every build, never stored or sent.
  final String password;

  @override
  State<PasswordStrengthBar> createState() => _PasswordStrengthBarState();
}

class _PasswordStrengthBarState extends State<PasswordStrengthBar>
    with WidgetsBindingObserver {
  late bool _reduceMotion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  @override
  void didChangeAccessibilityFeatures() => setState(_updateMotion);

  void _updateMotion() {
    _reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .reduceMotion;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final strength = scorePassword(widget.password);
    final color = strength.color(tokens);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(tokens.radiusSm / 2),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: strength.fraction),
            duration: _reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            builder: (context, value, _) {
              return LinearProgressIndicator(
                value: value,
                minHeight: 4,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(color),
              );
            },
          ),
        ),
        if (strength != PasswordStrength.empty) ...[
          SizedBox(height: tokens.spacingXs),
          Text(
            strength.label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ],
    );
  }
}
