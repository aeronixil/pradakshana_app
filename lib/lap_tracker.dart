import 'dart:math' as math;

class GpsFix {
  const GpsFix(this.latitude, this.longitude, this.accuracy, this.time);
  final double latitude, longitude, accuracy;
  final DateTime time;
}

class Lap {
  const Lap(this.finishedAt, this.distance, this.seconds);
  final DateTime finishedAt;
  final double distance;
  final int seconds;
}

/// Conservative outdoor loop detector. Coordinates never leave this object.
/// A loop must leave the start gate, enclose area, then return to the gate.
class LapTracker {
  LapTracker({this.minimumDistance = 80});
  final double minimumDistance;
  GpsFix? _anchor, _previous;
  DateTime? _lastTimestamp;
  double distance = 0;
  double _twiceArea = 0;
  bool _departed = false;
  String status = 'Waiting for an accurate GPS fix…';

  void reset() {
    _anchor = _previous = null;
    _lastTimestamp = null;
    distance = _twiceArea = 0;
    _departed = false;
  }

  void _begin(GpsFix fix) {
    _anchor = _previous = fix;
    distance = _twiceArea = 0;
    _departed = false;
  }

  math.Point<double> _point(GpsFix p) {
    const scale = 111195.0;
    return math.Point(
      (p.longitude - _anchor!.longitude) *
          scale *
          math.cos(_anchor!.latitude * math.pi / 180),
      (p.latitude - _anchor!.latitude) * scale,
    );
  }

  Lap? add(GpsFix fix, {required DateTime now}) {
    if (!fix.latitude.isFinite ||
        !fix.longitude.isFinite ||
        fix.latitude.abs() > 90 ||
        fix.longitude.abs() > 180 ||
        !fix.accuracy.isFinite ||
        fix.accuracy <= 0 ||
        fix.accuracy > 10) {
      status =
          'Weak GPS — move into the open (accuracy must be 10 m or better).';
      return null;
    }
    final age = now.difference(fix.time).inMilliseconds;
    if (age > 10000 ||
        age < -2000 ||
        (_lastTimestamp != null && !fix.time.isAfter(_lastTimestamp!))) {
      status = 'Waiting for a fresh GPS reading…';
      return null;
    }
    _lastTimestamp = fix.time;
    if (_previous == null) {
      _begin(fix);
      status = 'Start point set. Walk a full loop and return here.';
      return null;
    }
    final seconds = fix.time.difference(_previous!.time).inMilliseconds / 1000;
    if (seconds > 20) {
      _begin(fix);
      status = 'GPS gap — partial loop discarded. New start point set.';
      return null;
    }
    final p = _point(fix);
    final previous = _point(_previous!);
    final step = p.distanceTo(previous);
    if (step / seconds > 4.5) {
      reset();
      status = 'GPS jump or movement too fast. Waiting for a new start point.';
      return null;
    }
    // Avoid accumulating sub-metre stationary jitter.
    if (step < 2) return null;
    distance += step;
    _twiceArea += previous.x * p.y - p.x * previous.y;
    _previous = fix;
    if (p.magnitude >= 25) _departed = true;
    final elapsed = fix.time.difference(_anchor!.time).inSeconds;
    status = _departed
        ? 'Walking — return to your start to complete the loop.'
        : 'Walk at least 25 m away from your start point.';
    if (!_departed || p.magnitude > 10) return null;
    // Closing the polygon at the origin adds zero to its signed area.
    final area = _twiceArea.abs() / 2;
    final valid = distance >= minimumDistance &&
        elapsed >= 30 &&
        area >= math.max(100, distance * distance * 0.015);
    final lap = valid ? Lap(fix.time, distance, elapsed) : null;
    _begin(fix);
    status = valid
        ? 'Pradakshina logged. Keep walking for the next one.'
        : 'Returned to start, but no complete loop detected. Ready to try again.';
    return lap;
  }
}
