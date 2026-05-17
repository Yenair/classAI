import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:classai/core/services/ai_service.dart';
import 'package:classai/core/utils/encryption_utils.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockFunctionsClient extends Mock implements FunctionsClient {}

void main() {
  late MockSupabaseClient mockSupabase;
  late MockFunctionsClient mockFunctions;
  late Uint8List schoolKey;

  setUp(() {
    mockSupabase = MockSupabaseClient();
    mockFunctions = MockFunctionsClient();
    schoolKey = EncryptionUtils.generateKey();
    when(() => mockSupabase.functions).thenReturn(mockFunctions);
  });

  group('AiService encryption', () {
    test('AI responses encrypted when schoolKey is provided', () async {
      // Arrange
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

      final aiService = AiService(schoolKey: schoolKey, supabase: mockSupabase);

      // Act
      final result = await aiService.generate('Teach me something');

      // Assert
      expect(result['encryptedContent'], isA<String>());
      expect(result['encryptedContent'], isNotEmpty);
      expect(result['raw'], isA<Map<String, dynamic>>());

      // Verify the ciphertext can be decrypted
      final decrypted = await EncryptionUtils.decryptAesGcm(
        schoolKey,
        result['encryptedContent'] as String,
      );
      expect(decrypted, contains('Learn X'));
    });

    test('encryptedContent is a non-empty base64 string', () async {
      // Arrange
      when(() => mockFunctions.invoke('deepseek-proxy', body: any(named: 'body')))
          .thenAnswer((_) async => FunctionResponse(
                data: {
                  'generatedJson': {'objectives': ['Test']}
                },
                status: 200,
              ));

      final aiService = AiService(schoolKey: schoolKey, supabase: mockSupabase);

      // Act
      final result = await aiService.generate('Test prompt');

      // Assert
      expect(result['encryptedContent'], isA<String>());
      expect(result['encryptedContent'], isNotEmpty);
    });

    test('Responses NOT encrypted when schoolKey is null', () async {
      // Arrange
      when(() => mockFunctions.invoke('deepseek-proxy', body: any(named: 'body')))
          .thenAnswer((_) async => FunctionResponse(
                data: {
                  'generatedJson': {'objectives': ['Learn X']}
                },
                status: 200,
              ));

      final aiService = AiService(schoolKey: null, supabase: mockSupabase);

      // Act
      final result = await aiService.generate('Teach me something');

      // Assert — no encryption when schoolKey is null
      expect(result['encryptedContent'], isNull);
      expect(result['objectives'], contains('Learn X'));
    });
  });
}
