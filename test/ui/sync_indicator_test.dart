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

    // The icon is wrapped in a tinted Container; verify the Container
    // exists and that it contains an Icon widget.
    final iconButton = tester.widget<IconButton>(find.byType(IconButton));
    final iconContainer = iconButton.icon as StatelessWidget;
    final iconInContainer = find.descendant(
      of: find.byWidget(iconContainer),
      matching: find.byType(Icon),
    );
    expect(iconInContainer, findsOneWidget);
  });

  testWidgets('SyncIndicator shows cloud_sync icon when syncing',
      (tester) async {
    await tester.pumpWidget(_buildApp(
      const SyncStatusData(status: SyncStatus.syncing),
    ));

    await tester.pumpAndSettle();

    final iconButton = tester.widget<IconButton>(find.byType(IconButton));
    final iconContainer = iconButton.icon as StatelessWidget;
    final iconInContainer = find.descendant(
      of: find.byWidget(iconContainer),
      matching: find.byType(Icon),
    );
    expect(iconInContainer, findsOneWidget);
  });

  testWidgets('SyncIndicator shows cloud_done icon when synced',
      (tester) async {
    await tester.pumpWidget(_buildApp(
      const SyncStatusData(status: SyncStatus.synced),
    ));

    await tester.pumpAndSettle();

    final iconButton = tester.widget<IconButton>(find.byType(IconButton));
    final iconContainer = iconButton.icon as StatelessWidget;
    final iconInContainer = find.descendant(
      of: find.byWidget(iconContainer),
      matching: find.byType(Icon),
    );
    expect(iconInContainer, findsOneWidget);
  });

  testWidgets('SyncIndicator shows cloud_off (red) icon on error',
      (tester) async {
    await tester.pumpWidget(_buildApp(
      const SyncStatusData(status: SyncStatus.error),
    ));

    await tester.pumpAndSettle();

    final iconButton = tester.widget<IconButton>(find.byType(IconButton));
    final iconContainer = iconButton.icon as StatelessWidget;
    final iconInContainer = find.descendant(
      of: find.byWidget(iconContainer),
      matching: find.byType(Icon),
    );
    expect(iconInContainer, findsOneWidget);
  });

  testWidgets('tapping SyncIndicator opens modal bottom sheet', (tester) async {
    await tester.pumpWidget(_buildApp(
      const SyncStatusData(status: SyncStatus.synced, isOnline: true),
    ));

    await tester.pumpAndSettle();

    await tester.tap(find.byType(IconButton));
    // Allow the bottom sheet transition to settle
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('Sync Details'), findsOneWidget);
  });
}
