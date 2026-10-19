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
  test('GPS lap is automatically saved and route coordinates are not stored',
      () async {
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
    expect(raw, isNot(contains('latitude')));
    expect(raw, isNot(contains('longitude')));
    expect(jsonDecode(raw)[0]['events'][0]['source'], 'gps');
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
}
