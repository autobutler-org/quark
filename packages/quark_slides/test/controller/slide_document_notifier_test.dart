import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

void main() {
  test('every command, undo and redo notifies listeners', () {
    final notifier = SlideDocumentNotifier(Presentation());
    var notified = 0;
    notifier.addListener(() => notified++);
    final id = notifier.controller.addSlide();
    notifier.controller.setSlideNotes(id, 'hi');
    notifier.controller.undo();
    notifier.controller.redo();
    expect(notified, 4);
    expect(notifier.presentation.slides.single.notes, 'hi');
    notifier.dispose();
  });

  test('a command that changes nothing does not notify', () {
    final notifier = SlideDocumentNotifier(Presentation());
    final id = notifier.controller.addSlide();
    var notified = 0;
    notifier.addListener(() => notified++);
    notifier.controller.moveSlide(id, 0);
    expect(notified, 0);
    notifier.dispose();
  });

  test('passes the id generator and depth to the controller', () {
    final notifier = SlideDocumentNotifier(
      Presentation(),
      newId: () => 'fixed',
      maxUndoDepth: 7,
    );
    expect(notifier.controller.addSlide(), 'fixed');
    expect(notifier.controller.maxUndoDepth, 7);
    notifier.dispose();
  });

  test('the controller stops notifying once the notifier is disposed', () {
    final notifier = SlideDocumentNotifier(Presentation());
    final controller = notifier.controller;
    notifier.dispose();
    expect(controller.addSlide, returnsNormally);
  });
}
