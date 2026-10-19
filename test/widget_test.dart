import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pradakshana_app/hanuman_chalisa.dart';
import 'package:pradakshana_app/main.dart';
import 'package:pradakshana_app/session_controller.dart';
import 'lap_tracker_test.dart' as fixtures;
import 'session_controller_test.dart' show FakeLocation;

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
            .widget<TextField>(find.byKey(const Key('prayer-input')))
            .controller!
            .text,
        hanumanChalisa);
    await tester.tap(find.text('Read without GPS'));
    await tester.pumpAndSettle();
    final reader = find.byKey(const Key('prayer-reader'));
    expect(tester.widget<TextField>(reader).readOnly, true);
    expect(tester.getSize(reader).height, greaterThan(400));
    await tester.tap(find.byTooltip('Larger text'));
    await tester.pump();
    expect(tester.widget<TextField>(reader).style!.fontSize, 26);
    await tester.tap(find.text('Edit'));
    await tester.pump();
    await tester.enterText(reader, 'ॐ नमः शिवाय');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(reader).readOnly, true);
    await tester.tap(find.byTooltip('Session controls'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add manually'));
    await tester.pumpAndSettle();
    expect(find.text('1 pradakshinas'), findsOneWidget);
    await tester.tap(find.text('Correct −1'));
    await tester.pumpAndSettle();
    expect(find.text('0 pradakshinas'), findsOneWidget);
    await tester.tap(find.text('Finish session'));
    await tester.pumpAndSettle();
    expect(find.text('Insights'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('prayer-input')))
            .controller!
            .text,
        'ॐ नमः शिवाय');
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
    await tester.tap(find.text('Read & start GPS'));
    await tester.pumpAndSettle();
    expect(counter.tracking, true);
    final reader = find.byKey(const Key('prayer-reader'));
    final field = tester.widget<TextField>(reader);
    field.scrollController!.jumpTo(500);
    await tester.pump();
    final position = field.scrollController!.offset;
    for (final fix in fixtures.circle()) {
      time = fix.time;
      source.fixes.add(fix);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(counter.currentCount, 1);
    expect(find.text('1 pradakshinas'), findsOneWidget);
    expect(tester.widget<TextField>(reader).controller!.text, hanumanChalisa);
    expect(field.scrollController!.offset, position);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await source.fixes.close();
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
          prayer.isEmpty ? hanumanChalisa : prayer);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
