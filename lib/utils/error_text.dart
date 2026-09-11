import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Every user-facing error string in the app is produced here (#1622).
///
/// Pages and widgets must never build error copy themselves, and must never
/// put a thrown object into text a user reads. `'Save failed: $e'` renders
/// exception class names, OS errno values and full request URIs into the UI —
/// it tells the user nothing they can act on and leaks internals while doing
/// it. Call [Errors.message] instead and pass what the app was trying to do.
///
/// Centralizing has a second payoff: these strings are the app's entire
/// user-facing error vocabulary in one file, so translating them later is a
/// matter of swapping the bodies here for generated `AppLocalizations`
/// lookups, not of hunting sixty interpolations across twenty pages.
///
/// To extend: add a `static` method here, never a string at the call site.
abstract final class Errors {
  /// A short sentence for [error], safe to show a user.
  ///
  /// [action] names what the app was doing, as a bare verb phrase that reads
  /// after "Couldn't" — `'save the file'`, `'load your photos'`, `'delete the
  /// album'`. Lowercase, no trailing period.
  static String message(Object? error, String action) {
    if (error == null) return couldNot(action);
    if (isQuarkUnreachableError(error)) return quarkDisconnectedInline;
    if (error is UnauthorizedException) return sessionExpired;
    if (error is MessageException) return _sentence(error.message);
    if (error is ApiException) return _forStatus(error.statusCode, action);
    return couldNot(action);
  }

  /// The Quark writes its own copy in lowercase fragments — "server busy,
  /// please retry". Reshape it so it reads like the rest of the app's text.
  static String _sentence(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;
    final capitalized = trimmed[0].toUpperCase() + trimmed.substring(1);
    return '.!?'.contains(capitalized[capitalized.length - 1])
        ? capitalized
        : '$capitalized.';
  }

  /// The fallback: what the app was doing, and that it didn't work.
  static String couldNot(String action) => "Couldn't $action.";

  /// The zero-config connect form's own failure: an address that never
  /// answered is a typo as often as it is a sleeping Quark.
  static const String couldNotConnect =
      'Could not connect. Check the address and try again.';

  /// Headline above a [message], where a page has room for both.
  static const String somethingWentWrong = 'Something went wrong';

  /// Terse form, for a collapsed row whose expanded body carries the detail.
  static const String loadFailedShort = 'Failed to load';

  /// Playback copy. The format is the file's, not the Quark's, so these say so
  /// rather than routing the user through a connection or server explanation.
  static const String unsupportedAudioFormat =
      'Unable to play this audio file. The format may not be supported by '
      'this browser.';

  static const String unplayableMedia =
      'Unable to play this media. The file may use an unsupported '
      'codec/profile.';

  static String unsupportedVideoFormat(String extension) =>
      "This video format ($extension) isn't supported for in-browser "
      'playback. Download the file to watch it locally.';

  /// A restore the Quark refused with a 409: the item's original path is
  /// taken, and a restore never overwrites.
  static const String restoreConflict =
      'Something is already at that location. Move or rename it, then '
      'restore again.';

  /// A failed restore from the trash. A 409 gets [restoreConflict] — the
  /// generic "it changed while you were working" would send the user to retry
  /// something that will fail the same way. [action] is as in [message].
  static String restore(Object? error, String action) =>
      error is ApiException && error.statusCode == 409
      ? restoreConflict
      : message(error, action);

  /// Remote access is switched on but the Quark could not start it. The
  /// Quark's own reason is a diagnostic from the network layer, so it goes to
  /// the log and the user reads this instead.
  static const String remoteAccessFailing =
      "Remote access is on, but your Quark couldn't start it. Its log has "
      'the details.';

  /// Session gone. The router sends the user to login on the next navigation;
  /// this is what they read in the meantime.
  static const String sessionExpired = 'Your session expired. Sign in again.';

  /// The Quark answered, and what it said maps to copy worth the difference.
  /// Anything unmapped falls back to [couldNot] — a vague-but-true sentence
  /// beats a guess about a status the backend may not even return.
  static String _forStatus(int statusCode, String action) =>
      switch (statusCode) {
        401 => sessionExpired,
        403 => "You don't have permission to $action.",
        404 => "Couldn't $action — it's no longer there.",
        409 =>
          "Couldn't $action — it changed while you were working. Try again.",
        429 => 'Too many requests. Wait a moment and try again.',
        501 => "Your Quark doesn't support that yet.",
        503 => 'Your Quark is busy. Try again in a moment.',
        _ when statusCode >= 500 => 'Your Quark ran into a problem. Try again.',
        _ => couldNot(action),
      };
}

/// A failure whose text was written for a user to read.
///
/// Throw this from a service when the message itself is the useful part —
/// "Invalid username or password." — and [Errors.message] will pass it
/// through untouched. Everything else should be an [ApiException] or a plain
/// [Exception], whose text is for logs only.
class MessageException implements Exception {
  final String message;
  const MessageException(this.message);

  @override
  String toString() => message;
}

/// The Quark answered with a non-success status.
///
/// Carries the code so [Errors.message] can say something specific. The
/// [toString] is for `debugPrint` and crash logs, never for the UI.
class ApiException implements Exception {
  final int statusCode;

  /// What the caller was requesting, for logs — `'load photos'`.
  final String? context;

  const ApiException(this.statusCode, [this.context]);

  @override
  String toString() =>
      'ApiException($statusCode)${context == null ? '' : ': $context'}';
}

/// Throws the right exception for a response the Quark refused: its own
/// message when it sent one, its status code otherwise.
///
/// The Quark's `error` field is hand-written copy, never a Go error's text, so
/// it is safe to put in front of a user — [Errors.message] tidies it into a
/// sentence. [context] is for logs only.
Never throwApiError(int statusCode, Object? serverMessage, String context) {
  if (serverMessage is String && serverMessage.trim().isNotEmpty) {
    throw MessageException(serverMessage.trim());
  }
  throw ApiException(statusCode, context);
}
