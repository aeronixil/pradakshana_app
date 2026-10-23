import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pradakshana_app/hanuman_chalisa.dart';
import 'package:pradakshana_app/hanuman_chalisa_roman.dart';
import 'package:pradakshana_app/prayer_reader.dart';

void main() {
  final reader = find.byKey(const Key('prayer-reader'));
  TextField field(WidgetTester tester) => tester.widget<TextField>(reader);

  test('recitation includes opening, all forty verses and closing', () {
    expect(hanumanChalisaRoman, contains('Shri Guru charan saroj raj'));
    expect(hanumanChalisaRoman, contains('Buddhiheen tanu jaanike'));
    expect(hanumanChalisaRoman, contains('Jai Hanuman gyan gun sagar.'));
    final numbers = RegExp(r'\((\d+)\)')
        .allMatches(hanumanChalisaRoman)
        .map((match) => int.parse(match.group(1)!));
    expect(numbers, orderedEquals(List.generate(40, (index) => index + 1)));
    expect(hanumanChalisaRoman, contains('Pavan tanay sankat haran'));
    expect(hanumanChalisaRoman, contains('Siyavar Ramchandra ji ki jai.'));
  });

  testWidgets('script and size persist via preferences without changing prayer',
      (tester) async {
    var changes = 0, counts = 0;
    final preferences = <(bool, double)>[];
    Widget build() => MaterialApp(
            home: Scaffold(
                body: PrayerReader(
          text: hanumanChalisa,
          initialFontSize: 26,
          onChanged: (_) => changes++,
          onRead: (_) => counts++,
          onPreferencesChanged: (roman, size) => preferences.add((roman, size)),
        )));
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(field(tester).controller!.text, hanumanChalisaRoman);
    expect(field(tester).style!.fontSize, 26);
    final scroll = field(tester).scrollController!;
    scroll.jumpTo(400);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(scroll.offset, 400);
    await tester.tap(find.byTooltip('Reading options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Larger text'));
    await tester.pumpAndSettle();
    expect(preferences.last, (true, 28.0));
    expect(field(tester).style!.fontSize, 28);
    await tester.tap(find.byKey(const Key('reading-script')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('हिंदी').last);
    await tester.pumpAndSettle();
    expect(field(tester).controller!.text, hanumanChalisa);
    expect(preferences.last, (false, 28.0));
    expect(scroll.offset, 0);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(counts, 0);
    expect(changes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('custom prayer is preserved and can be edited', (tester) async {
    var prayer = 'My existing prayer';
    await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
                    body: PrayerReader(
                  text: prayer,
                  initialRoman: true,
                  onChanged: (value) => setState(() => prayer = value),
                )))));
    await tester.pumpAndSettle();
    expect(field(tester).controller!.text, prayer);
    expect(find.byKey(const Key('reading-script')), findsNothing);
    expect(find.text('Your text'), findsOneWidget);
    await tester.tap(find.byTooltip('Reading options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit text'));
    await tester.pumpAndSettle();
    await tester.enterText(reader, 'Jai Shri Ram');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(prayer, 'Jai Shri Ram');
    expect(field(tester).controller!.text, prayer);
    expect(field(tester).readOnly, true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opening and closing source editor preserves Roman recitation',
      (tester) async {
    var changes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PrayerReader(
                text: hanumanChalisa, onChanged: (_) => changes++))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reading options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit original Hindi text'));
    await tester.pumpAndSettle();
    expect(field(tester).controller!.text, hanumanChalisa);
    expect(field(tester).readOnly, false);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(field(tester).controller!.text, hanumanChalisaRoman);
    expect(changes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
