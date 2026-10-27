import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/music_play_threshold.dart';

Duration _s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

/// Feeds positions a second apart from [from] up to [to] and returns the
/// position updates on which [threshold] reported a play.
List<Duration> _listen(MusicPlayThreshold threshold, num from, num to) => [
  for (var t = from; t <= to; t++)
    if (threshold.update(_s(t))) _s(t),
];

/// When a song counts as played (#3284): 30 seconds, or half of a song
/// shorter than a minute; seeking and pausing add nothing.
void main() {
  test('the line is 30 seconds, or half a song under a minute', () {
    expect(MusicPlayThreshold.thresholdFor(_s(240)), _s(30));
    expect(MusicPlayThreshold.thresholdFor(_s(60)), _s(30));
    expect(MusicPlayThreshold.thresholdFor(_s(40)), _s(20));
    expect(MusicPlayThreshold.thresholdFor(null), _s(30));
    expect(MusicPlayThreshold.thresholdFor(Duration.zero), _s(30));
  });

  test('reports once, on the update that crosses the line', () {
    final threshold = MusicPlayThreshold(_s(240));
    expect(_listen(threshold, 0, 120), [_s(30)]);
  });

  test('a seek forward is not listening', () {
    final threshold = MusicPlayThreshold(_s(240));
    expect(_listen(threshold, 0, 10), isEmpty);
    expect(_listen(threshold, 200, 219), isEmpty);
    expect(threshold.listened, _s(29));
    expect(_listen(threshold, 220, 230), [_s(220)]);
  });

  test('a pause or a seek back adds nothing', () {
    final threshold = MusicPlayThreshold(_s(20));
    expect(_listen(threshold, 0, 5), isEmpty);
    expect(threshold.update(_s(5)), isFalse);
    expect(threshold.update(_s(1)), isFalse);
    expect(threshold.listened, _s(5));
    expect(_listen(threshold, 2, 5), isEmpty);
    expect(threshold.update(_s(6)), isTrue);
  });
}
