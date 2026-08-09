import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/widgets/credit_counter.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';

/// Test notifier extending OfflineCreditStateNotifier with fixed data.
class TestOfflineCreditStateNotifier extends OfflineCreditStateNotifier {
  final OfflineCreditStateData fixedData;

  TestOfflineCreditStateNotifier(this.fixedData);

  @override
  OfflineCreditStateData build() => fixedData;

  @override
  Future<void> refresh() async {
    // No-op for tests
  }
}

Widget _buildApp(OfflineCreditStateData data) {
  return ProviderScope(
    overrides: [
      offlineCreditStateProvider.overrideWith(
          () => TestOfflineCreditStateNotifier(data)),
    ],
    child: const MaterialApp(home: Scaffold(body: OfflineCreditCounter())),
  );
}

void main() {
  testWidgets('OfflineCreditCounter shows ActionChip with credit count',
      (tester) async {
    await tester.pumpWidget(_buildApp(
      const OfflineCreditStateData(currentOfflineCredits: 5),
    ));

    await tester.pumpAndSettle();

    expect(find.byType(ActionChip), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('OfflineCreditCounter shows loading indicator', (tester) async {
    await tester.pumpWidget(_buildApp(
      const OfflineCreditStateData(loading: true),
    ));

    await tester.pumpAndSettle();

    expect(find.text('…'), findsOneWidget);
  });

  testWidgets('tapping OfflineCreditCounter opens AlertDialog with details',
      (tester) async {
    await tester.pumpWidget(_buildApp(
      const OfflineCreditStateData(currentOfflineCredits: 10, tierName: 'Standard'),
    ));

    await tester.pumpAndSettle();

    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();

    expect(find.text('Offline Credits'), findsOneWidget);
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
      const OfflineCreditStateData(currentOfflineCredits: 10, tierName: 'Standard'),
    ));

    await tester.pumpAndSettle();

    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();

    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Upgrade'), findsOneWidget);
  });
}
