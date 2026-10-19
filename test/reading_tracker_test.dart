import 'package:flutter_test/flutter_test.dart';
import 'package:pradakshana_app/reading_tracker.dart';

void main() {
  test('full traversal counts once and returning to top rearms it', () {
    final tracker = ReadingTracker();
    for (var repetition = 0; repetition < 3; repetition++) {
      tracker.start(0);
      for (var i = 0; i < 10; i++) {
        expect(tracker.update(i / 10), false);
      }
      expect(tracker.update(1), true);
      expect(tracker.update(1), false);
      tracker.start(.9);
      expect(tracker.update(1), false);
    }
  });
  test('middle starts, end jumps and resets do not count', () {
    final tracker = ReadingTracker();
    tracker.start(.5);
    expect(tracker.update(1), false);
    tracker.start(0);
    expect(tracker.update(1), false);
    tracker.start(0);
    tracker.update(.1);
    tracker.reset();
    for (var i = 2; i <= 10; i++) {
      expect(tracker.update(i / 10), false);
    }
  });
}
