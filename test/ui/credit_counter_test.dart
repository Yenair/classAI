import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/widgets/credit_counter.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';

/// Test notifier extending CreditStateNotifier with fixed data.
class TestCreditStateNotifier extends CreditStateNotifier {
  final CreditStateData fixedData;

  TestCreditStateNotifier(this.fixedData);

  @override
  CreditStateData build() => fixedData;

  @override
  Future<void> refresh() async {
    // No-op for tests
  }
}

Widget _buildApp(CreditStateData data) {
  return ProviderScope(
    overrides: [
      creditStateProvider.overrideWith(() => TestCreditStateNotifier(data)),
    ],
    child: const MaterialApp(home: Scaffold(body: CreditCounter())),
  );
}

void main() {
  testWidgets('CreditCounter shows ActionChip with credit count',
      (tester) async {
    await tester.pumpWidget(_buildApp(
      const CreditStateData(currentCredits: 5),
    ));

    await tester.pumpAndSettle();

    expect(find.byType(ActionChip), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('CreditCounter shows loading indicator', (tester) async {
    await tester.pumpWidget(_buildApp(
      const CreditStateData(loading: true),
    ));

    await tester.pumpAndSettle();

    expect(find.text('…'), findsOneWidget);
  });

  testWidgets('tapping CreditCounter opens AlertDialog with details',
      (tester) async {
    await tester.pumpWidget(_buildApp(
      const CreditStateData(currentCredits: 10, tierName: 'Standard'),
    ));

    await tester.pumpAndSettle();

    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();

    expect(find.text('Credits'), findsOneWidget);
    // "10" appears in both ActionChip label & dialog; scope to AlertDialog
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
        find.descendant(of: dialog, matching: find.text('10')), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Upgrade'), findsOneWidget);
  });

  testWidgets('CreditDialog has Close and Upgrade buttons', (tester) async {
    await tester.pumpWidget(_buildApp(
      const CreditStateData(currentCredits: 10, tierName: 'Standard'),
    ));

    await tester.pumpAndSettle();

    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();

    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Upgrade'), findsOneWidget);
  });
}
