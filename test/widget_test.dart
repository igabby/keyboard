import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_app/main.dart';

void main() {
  testWidgets('remote keyboard shows connection controls and keys', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Device IP'), findsOneWidget);
    expect(find.text('Port'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
    expect(find.text('Backspace'), findsOneWidget);
    expect(find.text('Space'), findsOneWidget);
  });
}
