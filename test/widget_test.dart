import 'package:classai/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ClassAiApp shows loading screen initially', (tester) async {
    // The database future requires native plugins unavailable in test,
    // so the loading state will be shown immediately.
    await tester.pumpWidget(const ClassAiApp());

    expect(find.text('Starting ClassAI...'), findsOneWidget);
  });
}
