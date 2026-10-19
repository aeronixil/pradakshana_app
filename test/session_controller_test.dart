import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pradakshana_app/lap_tracker.dart';
import 'package:pradakshana_app/session_controller.dart';
import 'lap_tracker_test.dart' as fixtures;

class FakeLocation implements LocationSource {
  final fixes = StreamController<GpsFix>.broadcast(sync: true);
  Object? error;
  Completer<void>? permission;
  @override
  Future<void> prepare() async {
    if (permission != null) await permission!.future;
    if (error != null) throw error!;
  }

  @override
  Stream<GpsFix> watch() => fixes.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('manual counts, corrections and unfinished session survive restart',
      () async {
    final c = SessionController();
    await c.load();
    await c.begin('Temple', 'ॐ नमः शिवाय', 80);
    await c.adjust(-1);
    expect(c.currentCount, 0);
    await c.adjust(1);
    await c.adjust(1);
    await c.adjust(-1);
    c.dispose();
    final restored = SessionController();
    await restored.load();
    expect(restored.currentCount, 1);
    expect(restored.tracking, false);
    expect(restored.active!['prayer'], 'ॐ नमः शिवाय');
    await restored.finish();
    expect(restored.active, isNull);
    expect(restored.total, 1);
    restored.dispose();
  });
  test('GPS lap and timestamped local path survive restart', () async {
    final source = FakeLocation();
    var time = fixtures.epoch;
    final c = SessionController(location: source, now: () => time);
    await c.load();
    await c.begin('Temple', '', 80);
    await c.startGps();
    for (final f in fixtures.circle()) {
      time = f.time;
      source.fixes.add(f);
    }
    await c.save();
    expect(c.currentCount, 1);
    final raw = (await SharedPreferences.getInstance())
        .getString(SessionController.storageKey)!;
    final route = jsonDecode(raw)[0]['route'] as List;
    expect(route.length, greaterThan(60));
    expect(route.first['lat'], closeTo(12, .01));
    expect(route.first['at'], fixtures.epoch.toIso8601String());
    expect(jsonDecode(raw)[0]['events'][0]['source'], 'gps');
    final restored = SessionController();
    await restored.load();
    expect(restored.active!['route'], c.active!['route']);
    restored.dispose();
    await c.finish();
    expect(source.fixes.hasListener, false);
    c.dispose();
    await source.fixes.close();
  });
  test('denied location leaves manual counting available', () async {
    final source = FakeLocation()..error = StateError('Permission denied');
    final c = SessionController(location: source);
    await c.load();
    await c.begin('', '', 80);
    await c.startGps();
    expect(c.tracking, false);
    expect(c.status, contains('denied'));
    await c.adjust(1);
    expect(c.currentCount, 1);
    c.dispose();
    await source.fixes.close();
  });
  test('reading edits persist without changing counts or stopping GPS',
      () async {
    final source = FakeLocation();
    final c = SessionController(location: source);
    await c.load();
    await c.begin('Temple', 'Original', 80);
    await c.adjust(1);
    await c.startGps();
    await c.updatePrayer('Edited prayer');
    expect(c.tracking, true);
    expect(c.currentCount, 1);
    c.dispose();
    final restored = SessionController();
    await restored.load();
    expect(restored.active!['prayer'], 'Edited prayer');
    expect(restored.currentCount, 1);
    restored.dispose();
    await source.fixes.close();
  });
  test('finishing during permission request does not start a late tracker',
      () async {
    final source = FakeLocation()..permission = Completer<void>();
    final c = SessionController(location: source);
    await c.load();
    await c.begin('', '', 80);
    final pending = c.startGps();
    await c.finish();
    source.permission!.complete();
    await pending;
    expect(c.tracking, false);
    expect(source.fixes.hasListener, false);
    c.dispose();
    await source.fixes.close();
  });
  test('corrupt storage is preserved and new sessions blocked', () async {
    SharedPreferences.setMockInitialValues(
        {SessionController.storageKey: 'broken'});
    final c = SessionController();
    await c.load();
    await c.begin('', '', 80);
    expect(c.ready, false);
    expect(c.active, isNull);
    expect(c.storageError, isNotNull);
    expect(
        (await SharedPreferences.getInstance())
            .getString(SessionController.storageKey),
        'broken');
    c.dispose();
  });
  test('reading events are independent, corrected and restored', () async {
    final c = SessionController();
    await c.load();
    await c.begin('Temple', 'Prayer', 80);
    await c.adjustReading(-1);
    await c.adjustReading(1, source: 'scroll', language: 'English meaning');
    await c.adjustReading(1);
    await c.adjustReading(-1);
    expect(c.currentCount, 0);
    expect(c.currentReadings, 1);
    c.dispose();
    final restored = SessionController();
    await restored.load();
    expect(restored.currentReadings, 1);
    expect((restored.active!['readingEvents'] as List).first['language'],
        'English meaning');
    restored.dispose();
  });
  test('old sessions migrate without invented readings or paths', () async {
    SharedPreferences.setMockInitialValues({
      SessionController.storageKey: jsonEncode([
        {
          'startedAt': fixtures.epoch.toIso8601String(),
          'endedAt': null,
          'name': 'Old',
          'prayer': 'Saved',
          'minimumDistance': 80,
          'events': [
            {
              'delta': 1,
              'at': fixtures.epoch.toIso8601String(),
              'source': 'manual'
            }
          ],
        }
      ])
    });
    final c = SessionController();
    await c.load();
    expect(c.ready, true);
    expect(c.currentCount, 1);
    expect(c.currentReadings, 0);
    expect(c.active!['route'], isEmpty);
    c.dispose();
  });
  test('bad fixes excluded, gaps and pauses create disconnected segments',
      () async {
    final source = FakeLocation();
    var time = fixtures.epoch;
    final c = SessionController(location: source, now: () => time);
    await c.load();
    await c.begin('Temple', '', 80);
    await c.startGps();
    void feed(GpsFix fix) {
      time = fix.time;
      source.fixes.add(fix);
    }

    feed(fixtures.point(0, 0, 0));
    feed(fixtures.point(0, 4, 3));
    feed(fixtures.point(0, 8, 6, accuracy: 50));
    feed(fixtures.point(0, 12, 30));
    await c.pause();
    await c.startGps();
    feed(fixtures.point(0, 16, 35));
    final route = c.active!['route'] as List;
    expect(route.length, 4);
    expect(route[0]['segment'], route[1]['segment']);
    expect(route[2]['segment'], isNot(route[1]['segment']));
    expect(route[3]['segment'], isNot(route[2]['segment']));
    await c.pause();
    c.dispose();
    await source.fixes.close();
  });
}
