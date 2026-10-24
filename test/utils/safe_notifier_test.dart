import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';

class _Counter extends ChangeNotifier with SafeNotifier {}

void main() {
  test('notifies until disposed, then drops the call', () {
    final counter = _Counter();
    var heard = 0;
    counter.addListener(() => heard++);

    counter.notifyListeners();
    expect(heard, 1);
    expect(counter.isDisposed, isFalse);

    counter.dispose();
    expect(counter.isDisposed, isTrue);
    // A ChangeNotifier would throw here.
    counter.notifyListeners();
    expect(heard, 1);
  });
}
