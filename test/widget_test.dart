import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pradakshana_app/hanuman_chalisa.dart';
import 'package:pradakshana_app/hanuman_chalisa_roman.dart';
import 'package:pradakshana_app/main.dart';
import 'package:pradakshana_app/session_controller.dart';
import 'lap_tracker_test.dart' as fixtures;
import 'session_controller_test.dart' show FakeLocation;

class DelayedBeginController extends SessionController {
  final releaseBegin = Completer<void>();

  @override
  Future<void> begin(String name, String prayer, double minimum,
      {Map<String, dynamic>? place}) async {
    await super.begin(name, prayer, minimum, place: place);
    await releaseBegin.future;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('prefilled reader, editing, corrections and finish fit a phone',
      (tester) async {
    phone(tester);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('prayer-reader')))
            .controller!
            .text,
        hanumanChalisaRoman);
    final reader = find.byKey(const Key('prayer-reader'));
    expect(tester.widget<TextField>(reader).readOnly, true);
    expect(tester.getSize(reader).height, greaterThan(400));
    await tester.tap(find.byTooltip('Reading options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Larger text'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(reader).style!.fontSize, 26);
    await tester.tap(find.byTooltip('Reading options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit original Hindi text'));
    await tester.pumpAndSettle();
    await tester.enterText(reader, 'ॐ नमः शिवाय');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(reader).readOnly, true);
    expect(tester.widget<TextField>(reader).controller!.text, 'ॐ नमः शिवाय');
    expect(find.text('0 pradakshinas'), findsOneWidget);
    await tester.tap(find.byTooltip('Session controls'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add pradakshina'));
    await tester.pumpAndSettle();
    expect(find.text('1 pradakshinas'), findsOneWidget);
    await tester.tap(find.byTooltip('Subtract pradakshina'));
    await tester.pumpAndSettle();
    expect(find.text('0 pradakshinas'), findsOneWidget);
    await tester.tap(find.text('Finish session'));
    await tester.pumpAndSettle();
    expect(find.text('Insights'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(reader).controller!.text, 'ॐ नमः शिवाय');
    expect(tester.takeException(), isNull);
  });

  testWidgets('one tap starts GPS and automatic logs preserve reading position',
      (tester) async {
    phone(tester);
    final source = FakeLocation();
    var time = fixtures.epoch;
    final counter = SessionController(location: source, now: () => time);
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: counter)));
    await tester.pumpAndSettle();
    final reader = find.byKey(const Key('prayer-reader'));
    final beforeStart = tester.widget<TextField>(reader).scrollController;
    beforeStart!.jumpTo(500);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Begin pradakshina'));
    await tester.pumpAndSettle();
    expect(counter.tracking, true);
    final field = tester.widget<TextField>(reader);
    expect(identical(field.scrollController, beforeStart), true);
    expect(field.scrollController!.offset, 500);
    final position = field.scrollController!.offset;
    for (final fix in fixtures.circle()) {
      time = fix.time;
      source.fixes.add(fix);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(counter.currentCount, 1);
    expect(find.text('1 pradakshinas'), findsOneWidget);
    expect(
        tester.widget<TextField>(reader).controller!.text, hanumanChalisaRoman);
    expect(field.scrollController!.offset, position);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await source.fixes.close();
  });

  testWidgets(
      'editing while session starts keeps newer text and keyboard focus',
      (tester) async {
    phone(tester);
    final counter = DelayedBeginController();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: counter)));
    await tester.pumpAndSettle();
    final reader = find.byKey(const Key('prayer-reader'));
    await tester.tap(find.byTooltip('Reading options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit original Hindi text'));
    await tester.pumpAndSettle();

    await tester.enterText(reader, 'Jai Hanuman');
    await tester.pumpAndSettle();
    expect(counter.active!['prayer'], 'Jai Hanuman');
    expect(tester.widget<TextField>(reader).focusNode!.hasFocus, true);

    // Send another keyboard edit without refocusing while begin is still pending.
    tester.testTextInput.enterText('Jai Hanuman gyan gun sagar');
    await tester.pumpAndSettle();
    expect(counter.active!['prayer'], 'Jai Hanuman gyan gun sagar');
    counter.releaseBegin.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(reader).controller!.text,
        'Jai Hanuman gyan gun sagar');
    expect(counter.active!['prayer'], 'Jai Hanuman gyan gun sagar');
    expect(tester.widget<TextField>(reader).focusNode!.hasFocus, true);
    await counter.save();
    final saved = jsonDecode((await SharedPreferences.getInstance())
        .getString(SessionController.storageKey)!);
    expect(saved[0]['prayer'], 'Jai Hanuman gyan gun sagar');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'existing blank session gets Chalisa while custom reading is preserved',
      (tester) async {
    for (final prayer in ['', 'My existing prayer']) {
      SharedPreferences.setMockInitialValues({});
      final saved = SessionController();
      await saved.load();
      await saved.begin('Temple', prayer, 80);
      saved.dispose();
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('prayer-reader')))
              .controller!
              .text,
          prayer.isEmpty ? hanumanChalisaRoman : prayer);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'history reuses the marked place without carrying old counts or path',
      (tester) async {
    phone(tester);
    Map<String, dynamic> session(String name, int offset, double minimum) => {
          'name': name,
          'startedAt':
              fixtures.epoch.add(Duration(minutes: offset)).toIso8601String(),
          'endedAt': fixtures.epoch
              .add(Duration(minutes: offset + 1))
              .toIso8601String(),
          'prayer': hanumanChalisa,
          'minimumDistance': minimum,
          'events': [
            {
              'delta': 1,
              'source': 'manual',
              'at': fixtures.epoch.toIso8601String()
            }
          ],
          'readingEvents': [
            {
              'delta': 1,
              'source': 'manual',
              'at': fixtures.epoch.toIso8601String()
            }
          ],
          'route': [
            {
              'lat': 12.0 + offset / 1000,
              'lng': 77.0,
              'segment': 1,
              'at': fixtures.epoch
                  .add(Duration(minutes: offset))
                  .toIso8601String()
            }
          ],
        };
    SharedPreferences.setMockInitialValues({
      SessionController.storageKey: jsonEncode(
          [session('Home', 10, 80), session('Hanuman Temple', 0, 150)])
    });
    final source = FakeLocation();
    final counter = SessionController(
        location: source,
        now: () => fixtures.epoch.add(const Duration(days: 1)));
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: counter)));
    await tester.pumpAndSettle();
    expect(find.text('Home · saved start'), findsOneWidget);
    await tester.tap(find.byTooltip('Session controls'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History & insights'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Hanuman Temple ·').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this place again'));
    await tester.pumpAndSettle();
    expect(find.text('Hanuman Temple · saved start'), findsOneWidget);
    expect(counter.active, isNull);
    await tester.tap(find.text('Begin pradakshina'));
    await tester.pumpAndSettle();
    expect(counter.tracking, true);
    expect(counter.active!['name'], 'Hanuman Temple');
    expect(counter.active!['minimumDistance'], 150);
    expect(counter.active!['prayer'], hanumanChalisa);
    expect(counter.active!['place']['lat'], 12.0);
    expect(counter.active!['place']['lng'], 77.0);
    expect(counter.currentCount, 0);
    expect(counter.currentReadings, 0);
    expect(counter.active!['route'], isEmpty);
    expect(counter.sessions[2]['events'], hasLength(1));
    expect(counter.sessions[2]['route'], hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await source.fixes.close();
  });
}
