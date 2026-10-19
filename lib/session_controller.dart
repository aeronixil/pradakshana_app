import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'lap_tracker.dart';

abstract class LocationSource {
  Future<void> prepare();
  Stream<GpsFix> watch();
}

class DeviceLocation implements LocationSource {
  @override
  Future<void> prepare() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on location services, then try again.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError(
          'Location is blocked. Allow precise location in your app or browser settings.');
    }
    if (permission == LocationPermission.denied) {
      throw StateError(
          'Location permission was denied. You can still count manually.');
    }
  }

  @override
  Stream<GpsFix> watch() {
    LocationSettings settings = const LocationSettings(
        accuracy: LocationAccuracy.best, distanceFilter: 2);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 2,
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Pradakshina tracking is active',
          notificationText:
              'Return to the app to pause or finish your session.',
          enableWakeLock: true,
        ),
      );
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 2,
          activityType: ActivityType.fitness,
          allowBackgroundLocationUpdates: false);
    }
    return Geolocator.getPositionStream(locationSettings: settings)
        .map((p) => GpsFix(p.latitude, p.longitude, p.accuracy, p.timestamp));
  }
}

class SessionController extends ChangeNotifier {
  SessionController({LocationSource? location, DateTime Function()? now})
      : location = location ?? DeviceLocation(),
        now = now ?? DateTime.now;
  static const storageKey = 'pradakshina.sessions.v1';
  final LocationSource location;
  final DateTime Function() now;
  SharedPreferences? _preferences;
  List<Map<String, dynamic>> sessions = [];
  Map<String, dynamic>? active;
  LapTracker tracker = LapTracker();
  StreamSubscription<GpsFix>? _subscription;
  Timer? _watchdog;
  DateTime? _lastReceived;
  bool ready = false, busy = false, tracking = false, _disposed = false;
  int _generation = 0;
  int _segment = 0, _unsavedPoints = 0;
  static const routePointLimit = 12000;
  String status = 'Start a session to count your pradakshinas.';
  String? storageError;
  double? accuracy;
  Future<void> _writes = Future.value();

  int count(Map<String, dynamic> session) => (session['events'] as List)
      .fold(0, (sum, e) => sum + (e['delta'] as int));
  int get currentCount => active == null ? 0 : count(active!);
  int get total => sessions.fold(0, (sum, s) => sum + count(s));
  int readings(Map<String, dynamic> session) =>
      (session['readingEvents'] as List? ?? [])
          .fold(0, (sum, e) => sum + (e['delta'] as int));
  int get currentReadings => active == null ? 0 : readings(active!);
  int get totalReadings => sessions.fold(0, (sum, s) => sum + readings(s));
  bool get canBackground =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    try {
      _preferences = await SharedPreferences.getInstance();
      final raw = _preferences!.getString(storageKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as List;
        final loaded =
            decoded.map((s) => Map<String, dynamic>.from(s as Map)).toList();
        for (final s in loaded) {
          DateTime.parse(s['startedAt'] as String);
          if (s['name'] is! String ||
              s['prayer'] is! String ||
              s['minimumDistance'] is! num ||
              !(s['minimumDistance'] as num).isFinite ||
              (s['minimumDistance'] as num) < 60) {
            throw const FormatException('Invalid session');
          }
          if (s['endedAt'] != null) DateTime.parse(s['endedAt'] as String);
          for (final e in s['events'] as List) {
            if (e['delta'] is! int ||
                (e['delta'] != 1 && e['delta'] != -1) ||
                (e['source'] != 'gps' && e['source'] != 'manual')) {
              throw const FormatException('Invalid event');
            }
            DateTime.parse(e['at'] as String);
          }
          s.putIfAbsent('readingEvents', () => <dynamic>[]);
          s.putIfAbsent('route', () => <dynamic>[]);
          for (final e in s['readingEvents'] as List) {
            if (e['delta'] is! int ||
                (e['delta'] != 1 && e['delta'] != -1) ||
                (e['source'] != 'scroll' && e['source'] != 'manual')) {
              throw const FormatException('Invalid reading event');
            }
            DateTime.parse(e['at'] as String);
          }
          for (final p in s['route'] as List) {
            if (p['lat'] is! num ||
                p['lng'] is! num ||
                !(p['lat'] as num).isFinite ||
                !(p['lng'] as num).isFinite ||
                (p['lat'] as num).abs() > 90 ||
                (p['lng'] as num).abs() > 180 ||
                p['segment'] is! int) {
              throw const FormatException('Invalid route');
            }
            DateTime.parse(p['at'] as String);
          }
        }
        sessions = loaded;
        for (final s in sessions) {
          if (s['endedAt'] == null) active = s;
        }
        if (active != null) {
          status =
              'Previous session restored and paused. Completed counts are saved.';
        }
      }
      ready = true;
    } catch (_) {
      storageError =
          'Could not read saved history. Reload the app to try again; existing data has not been replaced.';
    }
    _notify();
  }

  Future<void> save() {
    final snapshot = jsonEncode(sessions);
    _writes = _writes.then((_) async {
      try {
        if (!await _preferences!.setString(storageKey, snapshot)) {
          throw StateError('Write failed');
        }
        storageError = null;
      } catch (_) {
        storageError =
            'History could not be saved. Keep this app open and tap Retry save.';
      }
      _notify();
    });
    return _writes;
  }

  Future<void> begin(String name, String prayer, double minimum) async {
    if (!ready || active != null) return;
    active = {
      'startedAt': now().toIso8601String(),
      'endedAt': null,
      'name': name.trim().isEmpty ? 'Pradakshina session' : name.trim(),
      'prayer': prayer,
      'minimumDistance': minimum,
      'events': <Map<String, dynamic>>[],
      'readingEvents': <Map<String, dynamic>>[],
      'route': <Map<String, dynamic>>[],
    };
    sessions.insert(0, active!);
    status = 'Session ready. Start GPS or use the manual counter.';
    _notify();
    await save();
  }

  Future<void> startGps() async {
    if (active == null || tracking || busy) return;
    final generation = ++_generation;
    busy = true;
    status = 'Requesting precise location…';
    _notify();
    try {
      await location.prepare();
      if (_disposed || generation != _generation || active == null) return;
      tracker = LapTracker(
          minimumDistance: (active!['minimumDistance'] as num).toDouble());
      accuracy = null;
      final route = active!['route'] as List;
      _segment = route.isEmpty ? 0 : (route.last['segment'] as int) + 1;
      tracking = true;
      _lastReceived = DateTime.now();
      status = tracker.status;
      _subscription = location.watch().listen((fix) {
        if (!tracking || generation != _generation) return;
        _lastReceived = DateTime.now();
        accuracy = fix.accuracy;
        final lap = tracker.add(fix, now: now());
        status = tracker.status;
        if (tracker.acceptedFix) _recordPoint(fix);
        if (lap != null) {
          (active!['events'] as List).add({
            'at': lap.finishedAt.toIso8601String(),
            'delta': 1,
            'source': 'gps',
            'startedAt': lap.finishedAt
                .subtract(Duration(seconds: lap.seconds))
                .toIso8601String(),
            'distance': lap.distance,
            'seconds': lap.seconds
          });
          unawaited(save());
        }
        _notify();
      }, onError: (Object error) {
        unawaited(pause(
            message:
                'GPS stopped. Check location permissions and services, then resume.'));
      }, onDone: () {
        if (tracking) {
          unawaited(pause(message: 'GPS stream ended. Resume to continue.'));
        }
      });
      _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
        if (DateTime.now().difference(_lastReceived!).inSeconds > 25) {
          tracker.reset();
          status =
              'No recent GPS readings. Waiting for signal; partial loop reset.';
          _notify();
        }
      });
    } catch (error) {
      if (_disposed || generation != _generation) return;
      tracking = false;
      status = error is StateError
          ? error.message.toString()
          : 'Could not start GPS. Check location access and try again.';
    } finally {
      if (generation == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> updatePrayer(String text) async {
    if (active == null || active!['prayer'] == text) return;
    active!['prayer'] = text;
    _notify();
    await save();
  }

  void _recordPoint(GpsFix fix) {
    final totalPoints =
        sessions.fold<int>(0, (sum, s) => sum + (s['route'] as List).length);
    if (totalPoints >= routePointLimit) {
      if (active!['routeFull'] != true) {
        active!['routeFull'] = true;
        unawaited(save());
      }
      return;
    }
    if (tracker.startsSegment) _segment++;
    (active!['route'] as List).add({
      'lat': double.parse(fix.latitude.toStringAsFixed(6)),
      'lng': double.parse(fix.longitude.toStringAsFixed(6)),
      'at': fix.time.toIso8601String(),
      'segment': _segment,
    });
    if (++_unsavedPoints >= 5) {
      _unsavedPoints = 0;
      unawaited(save());
    }
  }

  Future<void> adjustReading(int delta,
      {String source = 'manual', String? language}) async {
    if (active == null ||
        (delta != 1 && delta != -1) ||
        (delta < 0 && currentReadings == 0)) {
      return;
    }
    (active!['readingEvents'] as List).add({
      'at': now().toIso8601String(),
      'delta': delta,
      'source': source,
      if (language != null) 'language': language,
    });
    _notify();
    await save();
  }

  Future<void> clearRoute(Map<String, dynamic> session) async {
    session['route'] = <dynamic>[];
    session.remove('routeFull');
    _segment++;
    _notify();
    await save();
  }

  Future<void> pause({String? message}) async {
    ++_generation;
    tracking = false;
    busy = false;
    _watchdog?.cancel();
    final subscription = _subscription;
    _subscription = null;
    tracker.reset();
    status = message ??
        'Paused. Completed counts are saved; resume starts a fresh loop.';
    _notify();
    await subscription?.cancel();
    if (active != null) await save();
  }

  Future<void> adjust(int delta) async {
    if (active == null ||
        (delta != 1 && delta != -1) ||
        (delta < 0 && currentCount == 0)) {
      return;
    }
    tracker.reset();
    (active!['events'] as List).add(
        {'at': now().toIso8601String(), 'delta': delta, 'source': 'manual'});
    status = tracking
        ? 'Count adjusted. GPS will set a new start point.'
        : 'Manual count saved.';
    _notify();
    await save();
  }

  Future<void> finish() async {
    await pause();
    if (active == null) return;
    active!['endedAt'] = now().toIso8601String();
    active = null;
    status = 'Session finished and saved on this device.';
    _notify();
    await save();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _watchdog?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
