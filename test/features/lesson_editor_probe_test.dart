import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/config_provider.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/core/services/config_service.dart';
import 'package:classai/core/services/emergency_flush_service.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/features/lesson/screens/lesson_editor_screen.dart';
import 'package:classai/main.dart' show databaseProvider;

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockFunctionsClient extends Mock implements FunctionsClient {}

class FixedAuthNotifier extends AuthNotifier {
  FixedAuthNotifier(this.fixedState);
  final AuthStateData fixedState;
  @override
  AuthStateData build() => fixedState;
}

class _TestDailyCreditNotifier extends DailyCreditStateNotifier {
  @override
  DailyCreditStateData build() => const DailyCreditStateData();
}

AuthStateData _authState(String tier) {
  final now = DateTime.now();
  return AuthStateData(
    state: AuthState.authenticated,
    currentTeacher: Teacher(
      localId: 1,
      serverId: '00000000-0000-0000-0000-000000000001',
      email: 'teacher@test.com',
      teacherName: 'Test Teacher',
      role: 'teacher',
      schoolLocalId: 1,
      schoolServerId: '00000000-0000-0000-0000-000000000010',
      isActive: true,
      forcePasswordReset: false,
      passwordHashVersion: 1,
      schoolKeyWrapped: 'wrapped',
      lastCreditRefillDate: now,
      createdAt: now,
      updatedAt: now,
      updateCounter: 0,
      isDeleted: false,
      lastModifiedBy: null,
      themeMode: 'system',
    ),
    currentSchool: School(
      localId: 1,
      serverId: '00000000-0000-0000-0000-000000000010',
      schoolName: 'Test School',
      shortCode: 'TST',
      logoUrl: null,
      subscriptionTier: tier,
      activeCurriculum: 'nerdc',
      activeCurriculumVersion: '2024',
      totalSeats: 5,
      schoolMasterKeyWrapped: 'wrapped',
      adminRecoveryEmail: null,
      adminRecoveryEmailVerified: false,
      createdAt: now,
      updatedAt: now,
      updateCounter: 0,
      isDeleted: false,
      lastModifiedBy: null,
    ),
  );
}

final Map<String, dynamic> _defaultLessonResult = {
  'raw': {
    'objectives': ['Learn X'],
    'vocabulary': ['Term1'],
    'materials': ['Book'],
    'presentation': {'step1': 'Intro'},
    'assessment': 'Quiz',
    'homework': 'Worksheet',
  },
};

final Map<String, dynamic> _defaultQuestionsResult = {
  'raw': {
    'mcq': [
      {
        'question': 'What is 2 + 2?',
        'options': {'A': '3', 'B': '4', 'C': '5', 'D': '6'},
        'correct': 'B',
      },
    ],
    'theory': [
      {
        'question': 'Explain algebraic expressions.',
        'modelAnswer': 'An algebraic expression combines numbers and variables.',
      },
    ],
    'subjective': [
      {
        'question': 'Describe solving a linear equation.',
        'answer': 'Isolate the variable by applying inverse operations.',
      },
    ],
  },
};

Map<String, dynamic> _generatedLessonContent() {
  return {
    'objectives': ['Learn X'],
    'vocabulary': ['Term1'],
    'materials': ['Book'],
    'presentation': {'step1': 'Intro'},
    'assessment': 'Quiz',
    'homework': 'Worksheet',
    'questions': {
      'mcqs': [
        {
          'question': 'What is 2 + 2?',
          'options': {'A': '3', 'B': '4', 'C': '5', 'D': '6'},
          'correct': 'B',
        },
      ],
      'theory': [
        {
          'question': 'Explain algebraic expressions.',
          'modelAnswer': 'An algebraic expression combines numbers and variables.',
        },
      ],
      'subjective': <Map<String, dynamic>>[],
    },
    'references': [
      {'text': 'Original reference', 'origin': 'ai'},
    ],
    'diagrams': [
      {'description': 'A classroom diagram'},
    ],
  };
}

void _mockConnectivityChannel({bool isOnline = false}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'check') {
        return isOnline ? <String>['wifi'] : <String>['none'];
      }
      return null;
    },
  );
}

void main() {
  late AppDatabase db;
  final mockSupabase = MockSupabaseClient();
  final functions = MockFunctionsClient();

  setUpAll(() {
    when(() => functions.invoke('get-config')).thenThrow(
      FunctionException(status: 500),
    );
    when(() => mockSupabase.functions).thenReturn(functions);
  });

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.initialize();
    await db.securityConfigDao.updateConfig(offlineCredits: 10);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertGenerated({bool unlocked = true}) {
    return db.lessonsDao.insertLesson(
      LessonsCompanion.insert(
        subject: 'Mathematics',
        classLevel: 'JSS 1',
        week: 1,
        topic: 'Generated lesson',
        difficulty: 'medium',
        bloomsVerbs: 'Remember,Understand',
        curriculum: 'NERDC',
        content: jsonEncode(_generatedLessonContent()),
        status: const Value('generated'),
        isUnlocked: Value(unlocked),
        teacherServerId:
            const Value('00000000-0000-0000-0000-000000000001'),
        schoolServerId:
            const Value('00000000-0000-0000-0000-000000000010'),
      ),
    );
  }

  Widget buildApp({
    Future<Map<String, dynamic>> Function(String prompt)? generateCallback,
    AuthStateData? authState,
    int? lessonId,
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authProvider.overrideWith(
          () => FixedAuthNotifier(authState ?? _authState('elite')),
        ),
        configServiceProvider.overrideWithValue(
          ConfigService(client: mockSupabase),
        ),
        emergencyFlushServiceProvider.overrideWithValue(
          EmergencyFlushService(),
        ),
        dailyCreditStateProvider.overrideWith(
          () => _TestDailyCreditNotifier(),
        ),
      ],
      child: MaterialApp(
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(0.65),
          ),
          child: widget!,
        ),
        home: LessonEditorScreen(
          generateCallback: generateCallback,
          lessonId: lessonId,
        ),
      ),
    );
  }

  void dumpSlide(WidgetTester tester, String tag) {
    final buf = StringBuffer();
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      buf.writeln('$tag TEXT: ${t.data ?? t.textSpan?.toPlainText()}');
    }
    for (final e in tester.widgetList<EditableText>(
      find.byType(EditableText),
    )) {
      buf.writeln('$tag FIELD[${e.controller.text}]');
    }
    debugPrint(buf.toString());
  }

  Future<void> nextSlide(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Next lesson section'));
    await tester.pumpAndSettle();
  }

  testWidgets('PROBE A: generated+unlocked, walk all slides', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    SharedPreferences.setMockInitialValues({
      '00000000-0000-0000-0000-000000000001_lesson_visible_references': true,
      '00000000-0000-0000-0000-000000000001_lesson_visible_suggested_images':
          true,
    });
    final id = await insertGenerated(unlocked: true);
    _mockConnectivityChannel(isOnline: true);
    await tester.pumpWidget(buildApp(lessonId: id));
    await tester.pumpAndSettle();

    debugPrint('===A_SLIDE0===');
    dumpSlide(tester, 'A0');
    await nextSlide(tester);
    debugPrint('===A_SLIDE1===');
    dumpSlide(tester, 'A1');
    await nextSlide(tester);
    debugPrint('===A_SLIDE2===');
    dumpSlide(tester, 'A2');
    await nextSlide(tester);
    debugPrint('===A_SLIDE3===');
    dumpSlide(tester, 'A3');

    // Open FAB action menu.
    await tester.tap(find.byTooltip('Lesson actions'));
    await tester.pumpAndSettle();
    debugPrint('===A_FAB_MENU===');
    dumpSlide(tester, 'A Fab');
  });

  testWidgets('PROBE B: generated+locked fixture', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    final id = await insertGenerated(unlocked: false);
    _mockConnectivityChannel(isOnline: true);
    await tester.pumpWidget(buildApp(lessonId: id));
    await tester.pumpAndSettle();
    debugPrint('===B_LOCKED===');
    dumpSlide(tester, 'B');
  });

  testWidgets('PROBE C: fresh generate flow end state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    _mockConnectivityChannel(isOnline: true);
    await tester.pumpWidget(buildApp(
      generateCallback: (prompt) async {
        if (prompt.contains('## Learning Objectives')) {
          return _defaultLessonResult;
        }
        return _defaultQuestionsResult;
      },
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Algebraic Expressions');
    await tester.pump();
    await tester.ensureVisible(find.text('Create with AI'));
    await tester.tap(find.text('Create with AI'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    final toast = find.byType(SelectableText);
    if (toast.evaluate().isNotEmpty) {
      Navigator.of(tester.element(toast.first)).pop();
    }
    await tester.pumpAndSettle();
    debugPrint('===C_AFTER_GEN===');
    dumpSlide(tester, 'C0');
    await nextSlide(tester);
    debugPrint('===C_ASSESS===');
    dumpSlide(tester, 'C1');
  });

  testWidgets('PROBE D: basic tier assessment tab', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    final id = await insertGenerated(unlocked: true);
    _mockConnectivityChannel(isOnline: true);
    await tester.pumpWidget(buildApp(
      lessonId: id,
      authState: _authState('basic'),
    ));
    await tester.pumpAndSettle();
    await nextSlide(tester);
    debugPrint('===D_BASIC_ASSESS===');
    dumpSlide(tester, 'D');
  });
}
