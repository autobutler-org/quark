import 'package:quark/utils/error_text.dart';

/// What a device name has to look like: one DNS label of 1 to 63 lowercase
/// letters, numbers or hyphens, with at least one letter and no hyphen at
/// either end.
///
/// The Quark applies the same rule and refuses anything else with a 400
/// (#2344). It also refuses `localhost`, which [validateHostname] checks
/// beside this pattern.
final RegExp hostnamePattern = RegExp(
  r'^(?=.*[a-z])[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$',
);

/// The helper line under a device name field, stating the rule up front.
const String hostnameHint = 'Lowercase letters, numbers or hyphens';

/// Validator for a device name field: null when the Quark will accept
/// [value], otherwise the sentence to show under the field.
///
/// Surrounding spaces are ignored, as the field trims them before sending.
/// Nothing else is rewritten: an uppercase letter is refused rather than
/// quietly lowercased, so the name sent is the name the user typed.
String? validateHostname(String? value) {
  final hostname = value?.trim() ?? '';
  if (hostname.isEmpty) return 'Name is required';
  if (hostname == 'localhost' || !hostnamePattern.hasMatch(hostname)) {
    return Errors.invalidHostname;
  }
  return null;
}
