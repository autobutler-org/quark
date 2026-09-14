import 'package:flutter/foundation.dart';

/// A video format a conversion can write, as `TranscodeDialog` offers it.
@immutable
class TranscodeFormatOption {
  /// Creates the option for [format], shown as [label].
  const TranscodeFormatOption({required this.format, required this.label});

  /// The value the caller sends on: the file extension without the dot, such
  /// as `mov`.
  final String format;

  /// The display name on the format's chip, such as `MOV`.
  final String label;
}
