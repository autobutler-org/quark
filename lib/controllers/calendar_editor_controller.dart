import 'package:flutter/foundation.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The event form's state while it is open (#1144): the draft, which event it
/// edits, whether a save is in flight, and the errors to show.
///
/// It holds Save off until the draft keeps the rules a person can break: a
/// title, an end after the start, and a repeat that does not stop before the
/// first date. It words the last two and any failed save with `Errors`. Saving and deleting go through the functions it is
/// given, which are `CalendarController.save` and `delete` in the app.
class CalendarEditorController extends ChangeNotifier {
  CalendarEditorController({
    required CalendarEventDraft draft,
    required this.save,
    required this.delete,
    this.eventId,
  }) : _draft = draft,
       _savedRepeat = eventId == null ? null : draft.repeat;

  /// Saves a draft, as a new event or over [eventId].
  final Future<void> Function(CalendarEventDraft draft, {int? id}) save;

  /// Deletes event [eventId].
  final Future<void> Function(int id) delete;

  /// The event edited, or null for a new one.
  final int? eventId;

  /// The repeat the event was saved with, which says whether an edit reaches
  /// a whole series.
  final CalendarRepeat? _savedRepeat;

  CalendarEventDraft _draft;
  bool _isSaving = false;
  String? _saveError;

  CalendarEventDraft get draft => _draft;
  bool get isNew => eventId == null;
  bool get isSaving => _isSaving;

  /// Whether this edits a saved repeating event.
  bool get editsSeries =>
      _savedRepeat != null && _savedRepeat != CalendarRepeat.none;

  /// Whether Save can be pressed: the draft has a title, ends after it
  /// starts, stops repeating no earlier than its first date, and no save is
  /// in flight.
  bool get canSave =>
      _draft.title.trim().isNotEmpty &&
      _draft.endsAfterStart &&
      _draft.repeatEndsInTime &&
      !_isSaving;

  /// The times' error. An end before the start shows at once: the pickers
  /// make it easy to do by accident.
  String? get timeError =>
      _draft.endsAfterStart ? null : Errors.calendarEndBeforeStart;

  /// The repeat's end error, shown at once like [timeError]: moving the start
  /// can leave the end behind it.
  String? get repeatError =>
      _draft.repeatEndsInTime ? null : Errors.calendarRepeatEndsBeforeStart;

  /// A failed save's or delete's sentence, or null.
  String? get saveError => _saveError;

  /// Takes the form's latest draft.
  void update(CalendarEventDraft draft) {
    _draft = draft;
    _saveError = null;
    notifyListeners();
  }

  /// Saves the draft if it keeps the rules. True when it was saved and the
  /// form can close.
  Future<bool> submit() async {
    if (!canSave) return false;
    return _run(() => save(_draft, id: eventId), 'save the event');
  }

  /// Deletes the event. True when it is gone and the form can close.
  Future<bool> remove() async {
    final id = eventId;
    if (id == null) return false;
    return _run(() => delete(id), 'delete the event');
  }

  Future<bool> _run(Future<void> Function() action, String words) async {
    _isSaving = true;
    _saveError = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (e) {
      _saveError = Errors.message(e, words);
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
