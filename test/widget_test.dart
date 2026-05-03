import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/main.dart';

void main() {
  testWidgets('remote keyboard records key presses', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Device IP'), findsOneWidget);
    expect(find.text('Remote input preview'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'h'));
    await tester.tap(find.widgetWithText(FilledButton, 'i'));
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();

    expect(find.text('hi⌫'), findsOneWidget);
  });
}
