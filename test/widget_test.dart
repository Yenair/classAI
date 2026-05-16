import 'package:classai/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('status screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DatabaseStatusScreen(),
      ),
    );

    expect(find.text('Database OK'), findsOneWidget);
  });
}
