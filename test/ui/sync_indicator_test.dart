import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/widgets/sync_indicator.dart';
import 'package:classai/features/dashboard/providers/sync_status_provider.dart';

/// Test notifier extending SyncStatusNotifier with fixed data.
class TestSyncStatusNotifier extends SyncStatusNotifier {
  final SyncStatusData fixedData;

  TestSyncStatusNotifier(this.fixedData);

  @override
  SyncStatusData build() => fixedData;

  @override
  Future<void> refresh() async {
    // No-op for tests
  }
}

Widget _buildApp(SyncStatusData data) {
  return ProviderScope(
    overrides: [
      syncStatusProvider.overrideWith(() => TestSyncStatusNotifier(data)),
    ],
    child: const MaterialApp(home: Scaffold(body: SyncIndicator())),
  );
}

void main() {
  testWidgets('SyncIndicator shows cloud_off icon when offline',
      (tester) async {
    await tester.pumpWidget(_buildApp(
      const SyncStatusData(status: SyncStatus.offline),
    ));

    await tester.pumpAndSettle();

    final iconButton = tester.widget<IconButton>(find.byType(IconButton));
    final icon = iconButton.icon as Icon;
    expect(icon.icon, Icons.cloud_off);
  });

  testWidgets('SyncIndicator shows cloud_sync icon when syncing',
      (tester) async {
    await tester.pumpWidget(_buildApp(
      const SyncStatusData(status: SyncStatus.syncing),
    ));

    await tester.pumpAndSettle();

    final iconButton = tester.widget<IconButton>(find.byType(IconButton));
    final icon = iconButton.icon as Icon;
    expect(icon.icon, Icons.cloud_sync);
  });

  testWidgets('SyncIndicator shows cloud_done icon when synced',
      (tester) async {
    await tester.pumpWidget(_buildApp(
      const SyncStatusData(status: SyncStatus.synced),
    ));

    await tester.pumpAndSettle();

    final iconButton = tester.widget<IconButton>(find.byType(IconButton));
    final icon = iconButton.icon as Icon;
    expect(icon.icon, Icons.cloud_done);
  });

  testWidgets('SyncIndicator shows cloud_off (red) icon on error',
      (tester) async {
    await tester.pumpWidget(_buildApp(
      const SyncStatusData(status: SyncStatus.error),
    ));

    await tester.pumpAndSettle();

    final iconButton = tester.widget<IconButton>(find.byType(IconButton));
    final icon = iconButton.icon as Icon;
    expect(icon.icon, Icons.cloud_off);
  });

  testWidgets('tapping SyncIndicator opens modal bottom sheet',
      (tester) async {
    await tester.pumpWidget(_buildApp(
      const SyncStatusData(status: SyncStatus.synced, isOnline: true),
    ));

    await tester.pumpAndSettle();

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.text('Sync Details'), findsOneWidget);
  });
}
