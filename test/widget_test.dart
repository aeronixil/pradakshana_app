import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pradakshana_app/main.dart';

void main() {
  testWidgets('start, manually count, read prayer and finish on a narrow phone',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Temple');
    await tester.enterText(find.byType(TextField).at(1), 'ॐ नमः शिवाय');
    await tester.ensureVisible(find.text('Begin session'));
    await tester.tap(find.text('Begin session'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add manually'));
    await tester.tap(find.text('Add manually'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('ॐ नमः शिवाय'), findsOneWidget);
    await tester.tap(find.text('Correct −1'));
    await tester.pumpAndSettle();
    expect(find.text('0'), findsOneWidget);
    await tester.tap(find.text('Finish session'));
    await tester.pumpAndSettle();
    expect(find.text('Begin your practice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
