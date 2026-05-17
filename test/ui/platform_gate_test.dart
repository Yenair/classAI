import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:classai/core/utils/platform_helper.dart';

void main() {
  group('PlatformHelper', () {
    testWidgets('returns true when shortcut side >= 600', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return FutureBuilder<bool>(
                future: PlatformHelper.isEditorMode(context),
                builder: (_, snap) {
                  if (!snap.hasData) return const CircularProgressIndicator();
                  return Text(snap.data! ? 'Editor' : 'Reader');
                },
              );
            },
          ),
        ),
      );

      // Default screen size is 800x600, shortestSide=600 → Editor
      await tester.pump();
      expect(find.text('Editor'), findsOneWidget);
    });

    testWidgets('respects editor override', (tester) async {
      SharedPreferences.setMockInitialValues({
        'platform_mode_override': 'editor',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return FutureBuilder<bool>(
                future: PlatformHelper.isEditorMode(context),
                builder: (_, snap) {
                  if (!snap.hasData) return const CircularProgressIndicator();
                  return Text(snap.data! ? 'Editor' : 'Reader');
                },
              );
            },
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Editor'), findsOneWidget);
    });

    testWidgets('respects reader override', (tester) async {
      SharedPreferences.setMockInitialValues({
        'platform_mode_override': 'reader',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return FutureBuilder<bool>(
                future: PlatformHelper.isEditorMode(context),
                builder: (_, snap) {
                  if (!snap.hasData) return const CircularProgressIndicator();
                  return Text(snap.data! ? 'Editor' : 'Reader');
                },
              );
            },
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Reader'), findsOneWidget);
    });

    test('setModeOverride stores correctly', () async {
      SharedPreferences.setMockInitialValues({});
      await PlatformHelper.setModeOverride('reader');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('platform_mode_override'), 'reader');
    });

    test('clearModeOverride removes stored override', () async {
      SharedPreferences.setMockInitialValues({
        'platform_mode_override': 'editor',
      });
      await PlatformHelper.clearModeOverride();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('platform_mode_override'), false);
    });
  });
}
