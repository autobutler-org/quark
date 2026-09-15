import 'package:quark/utils/error_text.dart';

/// What a new account's username has to look like: up to 32 lowercase
/// letters, numbers, dots, dashes or underscores, starting with a letter or
/// number.
///
/// The Quark applies the same rule and refuses anything else with a 400
/// (#1946), for a first setup, an account request and an account an admin
/// creates alike. Accounts that predate the rule keep their names.
final RegExp newUsernamePattern = RegExp(r'^[a-z0-9][a-z0-9._-]{0,31}$');

/// The helper line under a new username field, stating the rule up front.
const String newUsernameHint =
    'Lowercase letters, numbers, dots, dashes or underscores';

/// Validator for a new account's username field: null when the Quark will
/// accept [value], otherwise the sentence to show under the field.
///
/// Surrounding spaces are ignored, as the form trims them before sending.
/// Nothing else is rewritten: an uppercase letter is refused rather than
/// quietly lowercased, so the name sent is the name the user typed.
String? validateNewUsername(String? value) {
  final username = value?.trim() ?? '';
  if (username.isEmpty) return 'Username is required';
  if (!newUsernamePattern.hasMatch(username)) return Errors.invalidUsername;
  return null;
}
