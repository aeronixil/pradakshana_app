import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pradakshana_app/main.dart';
import 'package:pradakshana_app/hanuman_chalisa.dart';
import 'package:pradakshana_app/hanuman_chalisa_english.dart';
import 'package:pradakshana_app/insights.dart';
import 'package:pradakshana_app/session_controller.dart';
import 'lap_tracker_test.dart' as fixtures;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
      'visible counter corrections and translation preserve original text',
      (tester) async {
    phone(tester);
    final c = SessionController();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read without GPS'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add pradakshina'));
    await tester.tap(find.byTooltip('Add reading'));
    await tester.pumpAndSettle();
    expect(c.currentCount, 1);
    expect(c.currentReadings, 1);
    await tester.tap(find.byTooltip('Subtract pradakshina'));
    await tester.tap(find.byTooltip('Subtract reading'));
    await tester.pumpAndSettle();
    expect(c.currentCount, 0);
    expect(c.currentReadings, 0);
    await tester.tap(find.byType(DropdownButton<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English meaning').last);
    await tester.pumpAndSettle();
    final field =
        tester.widget<TextField>(find.byKey(const Key('prayer-reader')));
    expect(field.controller!.text, hanumanChalisaEnglish);
    field.scrollController!
        .jumpTo(field.scrollController!.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(c.currentReadings, 0);
    expect(c.active!['prayer'], hanumanChalisa);
    await tester.tap(find.byType(DropdownButton<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('हिंदी').last);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('prayer-reader')))
            .controller!
            .text,
        hanumanChalisa);
    expect(c.currentReadings, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'actual reading gestures count repeats without bottom double counts',
      (tester) async {
    phone(tester);
    final c = SessionController();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read without GPS'));
    await tester.pumpAndSettle();
    final reader = find.byKey(const Key('prayer-reader'));
    for (var repetition = 1; repetition <= 2; repetition++) {
      final scroll = tester.widget<TextField>(reader).scrollController!;
      var attempts = 0;
      while (scroll.offset < scroll.position.maxScrollExtent - 1 &&
          attempts++ < 100) {
        await tester.timedDrag(
            reader, const Offset(0, -280), const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
      }
      expect(attempts, lessThan(100));
      expect(c.currentReadings, repetition);
      await tester.drag(reader, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(c.currentReadings, repetition);
      await tester.tap(find.byKey(const Key('read-again')));
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
    }
    expect(c.currentCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'map has distinct segments, timestamp slider and per-loop selection',
      (tester) async {
    phone(tester);
    final c = SessionController(
        now: () => fixtures.epoch.add(const Duration(minutes: 10)));
    final session = <String, dynamic>{
      'name': 'Test path',
      'startedAt': fixtures.epoch.toIso8601String(),
      'endedAt': null,
      'readingEvents': <dynamic>[],
      'route': [
        for (var segment = 0; segment < 2; segment++)
          for (final fix in fixtures.circle(offset: segment * 300))
            {
              'lat': fix.latitude,
              'lng': fix.longitude,
              'at': fix.time.toIso8601String(),
              'segment': segment
            },
      ],
      'events': [
        for (var i = 0; i < 2; i++)
          {
            'source': 'gps',
            'delta': 1,
            'distance': 188,
            'seconds': 216,
            'startedAt': fixtures.epoch
                .add(Duration(seconds: i * 300))
                .toIso8601String(),
            'at': fixtures.epoch
                .add(Duration(seconds: i * 300 + 216))
                .toIso8601String(),
          }
      ],
    };
    c.sessions = [session];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SessionPaths(
                session: session, controller: c, allowTiles: false))));
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsNothing);
    await tester.tap(find.text('Show map'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<PolylineLayer>(find.byType(PolylineLayer))
            .polylines
            .length,
        2);
    final slider = find.byKey(const Key('path-slider'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('path-time'))).data,
        contains(stamp(fixtures.epoch.toIso8601String())));
    await tester.ensureVisible(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('GPS loop 1').last);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<PolylineLayer>(find.byType(PolylineLayer))
            .polylines
            .length,
        1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
        MaterialApp(home: Insights(controller: c, session: session)));
    await tester.pumpAndSettle();
    expect(find.byType(DailyBars), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  test('distance omits the connection between separated segments', () {
    final route = [
      {'lat': 12.0, 'lng': 77.0, 'segment': 1},
      {'lat': 12.0001, 'lng': 77.0, 'segment': 1},
      {'lat': 13.0, 'lng': 78.0, 'segment': 2},
    ];
    expect(routeDistance(route), closeTo(11.1, .2));
  });
}
