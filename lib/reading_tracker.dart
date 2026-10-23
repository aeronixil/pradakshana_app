/// Counts a traversal, not proof of reading. Layout/programmatic scrolls are
/// ignored by the caller. A new traversal must begin near the top.
class ReadingTracker {
  bool armed = false;
  double furthest = 0;

  void reset() {
    armed = false;
    furthest = 0;
  }

  void start(double fraction) {
    if (fraction <= .03) {
      armed = true;
      furthest = 0;
    }
  }

  bool update(double fraction) {
    if (fraction <= .03) start(fraction);
    if (!armed) return false;
    // Reject jumps that skip large parts (e.g. dragging a scrollbar to the end).
    if (fraction > furthest + .20) {
      reset();
      return false;
    }
    if (fraction > furthest) furthest = fraction;
    if (fraction >= .995) {
      reset();
      return true;
    }
    return false;
  }
}
