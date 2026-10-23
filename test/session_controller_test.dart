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
    feed(fixtures.point(0, 14, 35));
    final route = c.active!['route'] as List;
    expect(route.length, 4);
    expect(route[0]['segment'], route[1]['segment']);
    expect(route[2]['segment'], isNot(route[1]['segment']));
    expect(route[3]['segment'], isNot(route[2]['segment']));
    await c.pause();
    c.dispose();
    await source.fixes.close();
  });

  test('first accurate fix marks a reusable place and new sessions start empty',
      () async {
    final source = FakeLocation();
    var time = fixtures.epoch;
    final c = SessionController(location: source, now: () => time);
    await c.load();
    await c.begin('Temple', 'My prayer', 150);
    await c.startGps();
    source.fixes.add(fixtures.point(0, 0, 0, accuracy: 50));
    expect(c.latestPlace, isNull);
    source.fixes.add(fixtures.point(0, 0, 0));
    final place = c.latestPlace!;
    expect(place['name'], 'Temple');
    expect(place['minimumDistance'], 150);
    expect(place['prayer'], 'My prayer');
    await c.adjust(1);
    await c.adjustReading(1);
    await c.finish();
    time = time.add(const Duration(days: 1));
    await c.begin('Temple', place['prayer'] as String, 150, place: place);
    expect(c.currentCount, 0);
    expect(c.currentReadings, 0);
    expect(c.active!['route'], isEmpty);
    expect(c.active!['place']['id'], place['id']);
    expect(c.places, hasLength(1));
    await c.renameCurrentPlace('Morning temple');
    expect(c.latestPlace!['name'], 'Morning temple');
    expect(c.sessions.last['name'], 'Temple');
    expect(c.sessions.last['place']['name'], 'Temple');
    c.dispose();
    await source.fixes.close();
  });

  test('saved start waits for a fresh nearby fix and never draws an old bridge',
      () async {
    final source = FakeLocation();
    var time = fixtures.epoch;
    final c = SessionController(location: source, now: () => time);
    await c.load();
    await c.begin('Temple', '', 80, place: {
      'id': 'temple',
      'name': 'Temple',
      'lat': 12.0,
      'lng': 77.0,
      'markedAt':
          fixtures.epoch.subtract(const Duration(days: 3)).toIso8601String(),
    });
    await c.startGps();
    source.fixes.add(fixtures.point(100, 0, 0));
    expect(c.active!['route'], isEmpty);
    expect(c.tracker.armed, false);
    expect(c.status, contains('100 m away'));
    time = fixtures.epoch.add(const Duration(minutes: 1));
    source.fixes.add(fixtures.point(0, 0, 0));
    expect(c.active!['route'], isEmpty);
    source.fixes.add(fixtures.point(0, 0, 60, accuracy: 20));
    expect(c.active!['route'], isEmpty);
    source.fixes.add(fixtures.point(0, 10, 60));
    expect(c.tracker.armed, true);
    final route = c.active!['route'] as List;
    expect(route, hasLength(1));
    expect(route.first['at'], time.toIso8601String());
    expect(route.first['lat'], closeTo(12 + 10 / 111195, .000001));
    await c.pause();
    await c.startGps();
    time = fixtures.epoch.add(const Duration(seconds: 65));
    source.fixes.add(fixtures.point(50, 0, 65));
    expect(c.tracker.armed, false);
    expect(route, hasLength(1));
    c.dispose();
    await source.fixes.close();
  });

  test('recent reliable position can remark; stale or paused position cannot',
      () async {
    final source = FakeLocation();
    var time = fixtures.epoch;
    final c = SessionController(location: source, now: () => time);
    await c.load();
    await c.begin('Temple', '', 80, place: {
      'id': 'old',
      'name': 'Temple',
      'lat': 12.0,
      'lng': 77.0,
      'markedAt': fixtures.epoch.toIso8601String(),
    });
    expect(await c.markCurrentPlace(), false);
    await c.startGps();
    source.fixes.add(fixtures.point(100, 0, 0));
    expect(c.canMarkCurrentPlace, true);
    expect(await c.markCurrentPlace(), true);
    expect(c.tracker.armed, true);
    expect(c.active!['place']['id'], isNot('old'));
    expect(c.active!['place']['lng'],
        closeTo(fixtures.point(100, 0, 0).longitude, 1e-9));
    time = time.add(const Duration(seconds: 11));
    expect(c.canMarkCurrentPlace, false);
    expect(await c.markCurrentPlace(), false);
    source.fixes.add(fixtures.point(100, 0, 11));
    expect(c.canMarkCurrentPlace, true);
    await c.pause();
    expect(await c.markCurrentPlace(), false);
    c.dispose();
    await source.fixes.close();
  });

  test('old paths migrate into stable places that survive route deletion',
      () async {
    SharedPreferences.setMockInitialValues({
      SessionController.storageKey: jsonEncode([
        {
          'startedAt': fixtures.epoch.toIso8601String(),
          'endedAt':
              fixtures.epoch.add(const Duration(minutes: 10)).toIso8601String(),
          'name': 'Old temple',
          'prayer': 'Saved',
          'minimumDistance': 80,
          'events': [],
          'route': [
            {
              'lat': 12.0,
              'lng': 77.0,
              'at': fixtures.epoch.toIso8601String(),
              'segment': 0
            }
          ],
        }
      ]),
    });
    final c = SessionController();
    await c.load();
    expect(c.preferredRoman, true);
    expect(c.preferredFontSize, 24);
    final id = c.latestPlace!['id'];
    expect(c.placeForSession(c.sessions.first)!['id'], id);
    await c.clearRoute(c.sessions.first);
    await c.updateReadingPreferences(roman: false, fontSize: 30);
    c.dispose();
    final restored = SessionController();
    await restored.load();
    expect(restored.ready, true);
    expect(restored.latestPlace!['id'], id);
    expect(restored.latestPlace!['name'], 'Old temple');
    expect(restored.sessions.first['route'], isEmpty);
    expect(restored.preferredRoman, false);
    expect(restored.preferredFontSize, 30);
    restored.dispose();
  });
}
