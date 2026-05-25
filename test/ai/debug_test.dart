import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:classai/core/services/ai_service.dart';
import 'package:classai/core/database/database.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockFunctionsClient extends Mock implements FunctionsClient {}

void main() {
  group('AiService debug', () {
    late MockSupabaseClient mockSupabase;
    late MockFunctionsClient mockFunctions;
    late AiService aiService;
    late AppDatabase db;

    setUp(() async {
      mockSupabase = MockSupabaseClient();
      mockFunctions = MockFunctionsClient();
      when(() => mockSupabase.functions).thenReturn(mockFunctions);
      db = AppDatabase.forTesting();
      await db.initialize();
      aiService = AiService(supabase: mockSupabase, db: db);
      addTearDown(db.close);
    });

    test('generate with mock returns map', () async {
      when(() => mockFunctions.invoke('deepseek-proxy', body: any(named: 'body')))
          .thenAnswer((_) async => FunctionResponse(
                data: {
                  'generatedJson': {
                    'objectives': ['Learn X'],
                    'vocabulary': ['term1']
                  }
                },
                status: 200,
              ));

      final result = await aiService.generate('Teach me something');

      print('RESULT TYPE: ${result.runtimeType}');
      print('RESULT: $result');

      expect(result, isNotNull);
      expect(result, isA<Map<String, dynamic>>());
    });

    test('generate with deepseek throw and gemini success', () async {
      when(() => mockFunctions.invoke('deepseek-proxy', body: any(named: 'body')))
          .thenThrow(FunctionException(status: 404));
      when(() => mockFunctions.invoke('gemini-proxy', body: any(named: 'body')))
          .thenAnswer((_) async => FunctionResponse(
                data: {
                  'generatedJson': {
                    'objectives': ['Learn Y'],
                    'vocabulary': ['term2']
                  }
                },
                status: 200,
              ));

      final result = await aiService.generate('Teach me something');

      print('RESULT TYPE: ${result.runtimeType}');
      print('RESULT: $result');

      expect(result, isNotNull);
      expect(result, isA<Map<String, dynamic>>());
    });
  });
}
