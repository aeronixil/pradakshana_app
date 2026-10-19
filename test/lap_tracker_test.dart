import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:pradakshana_app/lap_tracker.dart';

final epoch = DateTime.utc(2026, 10, 19);
GpsFix point(double x, double y, int seconds, {double accuracy = 4}) => GpsFix(
    12 + y / 111195,
    77 + x / (111195 * math.cos(12 * math.pi / 180)),
    accuracy,
    epoch.add(Duration(seconds: seconds)));
List<GpsFix> circle(
        {int rounds = 1,
        int offset = 0,
        bool reverse = false,
        double radius = 30}) =>
    List.generate(rounds * 72 + 1, (i) {
      final a = i * math.pi / 36 * (reverse ? -1 : 1);
      return point(
          radius * math.sin(a), radius * (1 - math.cos(a)), offset + i * 3);
    });
List<Lap> run(LapTracker tracker, Iterable<GpsFix> fixes) => [
      for (final fix in fixes)
        if (tracker.add(fix, now: fix.time) case final Lap lap) lap,
    ];

void main() {
  test('counts continuous clockwise and anticlockwise circuits once each', () {
    for (final reverse in [false, true]) {
      final laps = run(LapTracker(), circle(rounds: 3, reverse: reverse));
      expect(laps, hasLength(3));
      expect(laps.first.distance, greaterThan(150));
      expect(laps.first.seconds, greaterThan(30));
    }
  });
  test('stationary jitter and small circuits never count', () {
    expect(run(LapTracker(), circle(rounds: 20, radius: 3)), isEmpty);
  });
  test('out and back is not a pradakshina', () {
    final fixes = [
      for (var i = 0; i <= 40; i++) point(i * 3, 0, i * 3),
      for (var i = 1; i <= 40; i++) point(120 - i * 3, 0, 120 + i * 3)
    ];
    expect(run(LapTracker(), fixes), isEmpty);
  });
  test('partial circuit does not count', () {
    expect(run(LapTracker(), circle().take(40)), isEmpty);
  });
  test('configured minimum distance is enforced', () {
    expect(run(LapTracker(minimumDistance: 300), circle()), isEmpty);
  });
  test('inaccurate fixes cannot create a loop', () {
    expect(
        run(LapTracker(),
            circle().map((f) => GpsFix(f.latitude, f.longitude, 50, f.time))),
        isEmpty);
  });
  test('cached, duplicate and invalid fixes are rejected', () {
    final tracker = LapTracker();
    final fix = point(0, 0, 0);
    expect(
        tracker.add(fix, now: epoch.add(const Duration(minutes: 1))), isNull);
    expect(tracker.distance, 0);
    tracker.add(fix, now: epoch);
    tracker.add(point(10, 0, 0), now: epoch);
    tracker.add(GpsFix(double.nan, 77, 5, epoch), now: epoch);
    expect(tracker.distance, 0);
  });
  test('GPS gap resets partial circuit without bridging the gap', () {
    final tracker = LapTracker();
    final fixes = circle();
    run(tracker, fixes.take(36));
    final afterGap = fixes.skip(36).map((f) => GpsFix(f.latitude, f.longitude,
        f.accuracy, f.time.add(const Duration(minutes: 2))));
    expect(run(tracker, afterGap), isEmpty);
  });
  test('fast jumps reset instead of counting transport as walking', () {
    final tracker = LapTracker();
    tracker.add(point(0, 0, 0), now: epoch);
    tracker.add(point(200, 0, 2), now: epoch.add(const Duration(seconds: 2)));
    expect(tracker.distance, 0);
    expect(tracker.status, contains('too fast'));
  });
  test('pause resets partial loop and new complete circuit can count', () {
    final tracker = LapTracker();
    run(tracker, circle().take(35));
    tracker.reset();
    expect(run(tracker, circle(offset: 300)), hasLength(1));
  });
}
