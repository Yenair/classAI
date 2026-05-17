import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/sanitization_utils.dart';
import '../utils/token_counter.dart';
import '../utils/encryption_utils.dart';

class AiService {
  final Uint8List? _schoolKey;
  final SupabaseClient _supabase;

  AiService({Uint8List? schoolKey, SupabaseClient? supabase})
      : _schoolKey = schoolKey,
        _supabase = supabase ?? Supabase.instance.client;

  Future<Map<String, dynamic>> generate(String prompt) async {
    // 1. Sanitize
    final injections = SanitizationUtils.findInjections(prompt);
    if (injections.isNotEmpty) throw AiInjectionException(injections);

    // 2. Truncate
    final truncated = TokenCounter.truncateIfNeeded(prompt, 4096);

    // 3. DeepSeek → Gemini fallback
    try {
      return await _callDeepSeek(truncated);
    } catch (_) {
      try {
        return await _callGemini(truncated);
      } catch (e) {
        throw AiGenerationException('Both providers failed: $e');
      }
    }
  }

  Future<Map<String, dynamic>> _callDeepSeek(String prompt) async {
    try {
      final response = await _supabase.functions.invoke('deepseek-proxy', body: {
        'prompt': prompt,
      });
      final data = response.data as Map<String, dynamic>;
      final generated = data['generatedJson'] as Map<String, dynamic>;
      return _encrypt(generated);
    } catch (_) {
      throw AiGenerationException('DeepSeek proxy not available');
    }
  }

  Future<Map<String, dynamic>> _callGemini(String prompt) async {
    try {
      final response = await _supabase.functions.invoke('gemini-proxy', body: {
        'prompt': prompt,
      });
      final data = response.data as Map<String, dynamic>;
      final generated = data['generatedJson'] as Map<String, dynamic>;
      return _encrypt(generated);
    } catch (_) {
      throw AiGenerationException('Gemini proxy not available');
    }
  }

  Future<Map<String, dynamic>> _encrypt(Map<String, dynamic> parsed) async {
    if (_schoolKey == null) return parsed;
    final rawStr = jsonEncode(parsed);
    final ciphertext = await EncryptionUtils.encryptAesGcm(_schoolKey, rawStr);
    return {
      'encryptedContent': ciphertext,
      'raw': parsed,
    };
  }
}

class AiInjectionException implements Exception {
  final List<String> patterns;
  AiInjectionException(this.patterns);

  @override
  String toString() => 'AI injection detected: $patterns';
}

class AiGenerationException implements Exception {
  final String message;
  AiGenerationException(this.message);

  @override
  String toString() => 'AI generation failed: $message';
}
