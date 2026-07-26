import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart';
import '../utils/sanitization_utils.dart';
import '../utils/token_counter.dart';
import '../utils/encryption_utils.dart';
import 'auth_service.dart';

class AiService {
  final Uint8List? _schoolKey;
  final SupabaseClient _supabase;
  final AppDatabase _db;

  AiService(
      {Uint8List? schoolKey, SupabaseClient? supabase, required AppDatabase db})
      : _schoolKey = schoolKey,
        _supabase = supabase ?? Supabase.instance.client,
        _db = db;

  /// Check if generation is allowed based on daily limit.
  /// Returns true if allowed, throws exception if limit exceeded.
  Future<bool> checkDailyLimit(String tier) async {
    final allowed = await _db.securityConfigDao
        .checkAndIncrementDailyGenerations(tier: tier);
    if (!allowed) {
      throw AiGenerationException(
          'Daily generation limit reached. Try again tomorrow.');
    }
    return true;
  }

  /// Log an audit entry for AI generation.
  Future<void> logGeneration(
      {required String? teacherId,
      required String? schoolId,
      required String topic}) async {
    final id = const Uuid().v4();
    await _db.auditLogsDao.insert(
      AuditLogsCompanion.insert(
        id: Value(id),
        teacherId: Value(teacherId),
        schoolId: Value(schoolId),
        action: Value('ai_generation'),
        metadata: Value(jsonEncode({
          'topic': topic,
          'timestamp': DateTime.now().toIso8601String(),
        })),
      ),
    );
  }

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

  /// Strip extraneous markdown code fences and introductory/concluding text
  /// from an AI response string before JSON parsing.
  String _stripMarkdownWrappers(String raw) {
    // Remove ```json ... ``` blocks
    final jsonFencePattern = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
    final jsonFenceMatch = jsonFencePattern.firstMatch(raw);
    if (jsonFenceMatch != null) {
      return jsonFenceMatch.group(1)!.trim();
    }

    // Remove "Here is the..." or "Here are the..." type wrappers
    final introPattern = RegExp(r'^.*?(?=\{)', dotAll: true);
    final introMatch = introPattern.firstMatch(raw);
    if (introMatch != null && introMatch.group(0)!.trim().isNotEmpty) {
      final afterIntro = raw.substring(introMatch.end).trim();
      if (afterIntro.startsWith('{') || afterIntro.startsWith('[')) {
        return afterIntro;
      }
    }

    return raw.trim();
  }

  Future<Map<String, dynamic>> _callDeepSeek(String prompt) async {
    // The proxy functions require the custom ClassAI JWT as a Bearer token in
    // the Authorization header. Read it from the static singleton so we don't
    // need to thread it through every call site (consistent with PaymentService).
    final jwt = SupabaseAuthService().currentJwt;
    final headers = <String, String>{};
    if (jwt != null && jwt.isNotEmpty) {
      headers['Authorization'] = 'Bearer $jwt';
    }
    final response = await _supabase.functions.invoke(
      'deepseek-proxy',
      headers: headers.isNotEmpty ? headers : null,
      body: {
        'prompt': prompt,
      },
    );
    final data = response.data as Map<String, dynamic>?;
    if (data == null || data['error'] != null) {
      throw AiGenerationException(
          data?['error'] as String? ?? 'DeepSeek proxy not available');
    }
    final generatedJson = data['generatedJson'];
    Map<String, dynamic> generated;
    if (generatedJson is String) {
      // Response came as raw text — strip wrappers and parse
      final stripped = _stripMarkdownWrappers(generatedJson);
      generated = Map<String, dynamic>.from(jsonDecode(stripped) as Map);
    } else {
      generated = generatedJson as Map<String, dynamic>;
    }
    return _encrypt(generated);
  }

  Future<Map<String, dynamic>> _callGemini(String prompt) async {
    // Same JWT injection as _callDeepSeek — see note above.
    final jwt = SupabaseAuthService().currentJwt;
    final headers = <String, String>{};
    if (jwt != null && jwt.isNotEmpty) {
      headers['Authorization'] = 'Bearer $jwt';
    }
    final response = await _supabase.functions.invoke(
      'gemini-proxy',
      headers: headers.isNotEmpty ? headers : null,
      body: {
        'prompt': prompt,
      },
    );
    final data = response.data as Map<String, dynamic>?;
    if (data == null || data['error'] != null) {
      throw AiGenerationException(
          data?['error'] as String? ?? 'Gemini proxy not available');
    }
    final generatedJson = data['generatedJson'];
    Map<String, dynamic> generated;
    if (generatedJson is String) {
      // Response came as raw text — strip wrappers and parse
      final stripped = _stripMarkdownWrappers(generatedJson);
      generated = Map<String, dynamic>.from(jsonDecode(stripped) as Map);
    } else {
      generated = generatedJson as Map<String, dynamic>;
    }
    return _encrypt(generated);
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
