import 'dart:math';
import 'package:classai/core/database/database.dart';
import 'package:drift/drift.dart';

/// USSD recovery concept for ClassAI.
///
/// ## Overview
/// USSD (Unstructured Supplementary Service Data) provides a universal
/// recovery mechanism that works on any mobile phone, including feature
/// phones without smartphones or internet connectivity. This is critical
/// for Nigerian schools where many teachers use basic mobile phones.
///
/// ## Flow
/// 1. Teacher dials a USSD code (e.g., *347*1#) from their registered
///    phone number.
/// 2. The USSD gateway identifies the phone number and presents a menu:
///    - Option 1: Reset Password
///    - Option 2: Get Activation Code
///    - Option 3: Account Status
/// 3. The teacher selects an option and follows the prompts.
/// 4. The USSD gateway calls the ClassAI USSD API endpoint.
/// 5. The response is rendered as a USSD menu.
///
/// ## API Endpoint
/// Designed to be called by a USSD gateway (e.g., Africa's Talking,
/// Arisenn, or directly via telco integration).
///
/// ## Limitations (Phase 8)
/// - This is a **concept implementation** only.
/// - Full USSD integration requires a telco agreement and gateway setup.
/// - The API endpoint is defined here for future integration.
/// - No actual USSD gateway is called during this phase.
///
/// ## Future Integration
/// When ready, deploy the USSD endpoint as a Supabase Edge Function
/// and configure the USSD gateway to forward requests to it.
class UssdRecoveryService {
  final AppDatabase _db;

  UssdRecoveryService(this._db);

  /// Generates a 6-digit recovery code for a teacher identified by
  /// [phoneNumber].
  ///
  /// Looks up the teacher by phone number in the teacher_devices or
  /// teachers table. If found, generates a random 6-digit code, stores
  /// it in the recovery_codes table with a 10-minute expiry, and returns
  /// the code string.
  ///
  /// Returns `null` if no teacher is found for the given phone number.
  Future<String?> generateRecoveryCodeForTeacher(
      String phoneNumber) async {
    try {
      // Look up the teacher by scanning teacher devices that match the
      // phone number as a device ID, or fall back to scanning teachers
      // by email if the phone number looks like an email.
      Teacher? teacher;

      if (phoneNumber.contains('@')) {
        // Phone number field may actually be an email in some deployments.
        final teachers = await _db.teachersDao.getAll();
        teacher = teachers.cast<Teacher?>().firstWhere(
              (t) => t!.email.toLowerCase() == phoneNumber.toLowerCase(),
              orElse: () => null,
            );
      } else {
        // Search teacher_devices for a matching device ID (phone number).
        final devices = await (_db.select(_db.teacherDevices)
              ..where((t) => t.deviceId.equals(phoneNumber)))
            .get();
        if (devices.isNotEmpty) {
          teacher = await _db.teachersDao.getById(devices.first.teacherId);
        }
      }

      if (teacher == null) return null;

      // Generate a random 6-digit code
      final random = Random.secure();
      final code = List.generate(6, (_) => random.nextInt(10)).join();

      final expiresAt = DateTime.now().add(const Duration(minutes: 10));

      // Store the code in the recovery_codes table using raw insert
      // since the generated DAO only has the id column.
      await _db.customInsert(
        'INSERT INTO recovery_codes '
        '(phone_number, code, expires_at, used, teacher_local_id, created_at) '
        'VALUES (?, ?, ?, 0, ?, ?)',
        variables: [
          Variable<String>(phoneNumber),
          Variable<String>(code),
          Variable<String>(expiresAt.toIso8601String()),
          Variable<int>(teacher.localId),
          Variable<String>(DateTime.now().toIso8601String()),
        ],
      );

      return code;
    } catch (e) {
      // Log and rethrow — caller should handle gracefully
      throw Exception('Failed to generate recovery code: $e');
    }
  }

  /// Verifies a 6-digit [code] for the given [phoneNumber].
  ///
  /// Checks the recovery_codes table for a matching, unexpired, unused
  /// code. If found, marks it as used and returns `true`. Otherwise
  /// returns `false`.
  Future<bool> verifyRecoveryCode(
      String phoneNumber, String code) async {
    try {
      final now = DateTime.now().toIso8601String();

      final result = await _db.customSelect(
        'SELECT id FROM recovery_codes '
        'WHERE phone_number = ? '
        'AND code = ? '
        'AND used = 0 '
        'AND expires_at > ? '
        'ORDER BY id DESC LIMIT 1',
        variables: [
          Variable<String>(phoneNumber),
          Variable<String>(code),
          Variable<String>(now),
        ],
      );

      final rows = await result.get();
      if (rows.isEmpty) return false;

      // Mark the code as used
      final codeId = rows.first.read<int>('id');
      await _db.customUpdate(
        'UPDATE recovery_codes SET used = 1 WHERE id = ?',
        variables: [Variable<int>(codeId)],
      );

      return true;
    } catch (e) {
      // Log and rethrow — caller should handle gracefully
      throw Exception('Failed to verify recovery code: $e');
    }
  }

  /// Handle an incoming USSD request.
  ///
  /// [sessionId] - Unique session ID from the USSD gateway.
  /// [phoneNumber] - The caller's phone number (MSISDN).
  /// [text] - The text input from the user so far.
  ///   - First request: empty string
  ///   - Subsequent requests: the full input string
  ///
  /// Returns a USSD response with:
  /// - `message`: the USSD menu text
  /// - `type`: 'response' (expects more input) or 'release' (end session)
  ///
  /// This method follows the Africa's Talking USSD API format,
  /// which is widely used across Nigerian telcos.
  UssdResponse handleUssdRequest({
    required String sessionId,
    required String phoneNumber,
    required String text,
  }) {
    // Parse the text to determine menu level
    final parts = text.isEmpty ? <String>[] : text.split('*');

    if (text.isEmpty) {
      // Main menu
      return UssdResponse(
        message:
            'Welcome to ClassAI Recovery\n\n'
            '1. Reset Password\n'
            '2. Get Activation Code\n'
            '3. Account Status\n\n'
            'Reply with option number:',
        type: UssdResponseType.response,
      );
    }

    // Process menu selections
    switch (parts.length) {
      case 1:
        return _handleMainMenu(parts[0], phoneNumber);
      case 2:
        return _handleSubMenu(parts[0], parts[1], phoneNumber);
      default:
        return UssdResponse(
          message: 'Invalid input. Please try again.',
          type: UssdResponseType.release,
        );
    }
  }

  UssdResponse _handleMainMenu(String option, String phoneNumber) {
    switch (option) {
      case '1':
        return UssdResponse(
          message:
              'Reset Password\n\n'
              'Enter your teacher ID or registered email:',
          type: UssdResponseType.response,
        );
      case '2':
        return UssdResponse(
          message:
              'Get Activation Code\n\n'
              'Enter your school short code:',
          type: UssdResponseType.response,
        );
      case '3':
        return UssdResponse(
          message:
              'Account Status\n\n'
              'Your account status will be sent via SMS '
              'to $phoneNumber within 5 minutes.',
          type: UssdResponseType.release,
        );
      default:
        return UssdResponse(
          message:
              'Invalid option. Please try again.\n\n'
              '1. Reset Password\n'
              '2. Get Activation Code\n'
              '3. Account Status',
          type: UssdResponseType.response,
        );
    }
  }

  UssdResponse _handleSubMenu(
      String option, String input, String phoneNumber) {
    switch (option) {
      case '1':
        // Password reset confirmation
        return UssdResponse(
          message:
              'A password reset link will be sent via SMS '
              'to $phoneNumber.\n\n'
              'Thank you for using ClassAI Recovery.',
          type: UssdResponseType.release,
        );
      case '2':
        // Activation code sent via SMS
        return UssdResponse(
          message:
              'Your activation code will be sent via SMS '
              'to $phoneNumber.\n\n'
              'Thank you for using ClassAI Recovery.',
          type: UssdResponseType.release,
        );
      default:
        return UssdResponse(
          message: 'Invalid input. Session ended.',
          type: UssdResponseType.release,
        );
    }
  }
}

/// Response from a USSD request.
class UssdResponse {
  final String message;
  final UssdResponseType type;

  const UssdResponse({
    required this.message,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'message': message,
        'type': type == UssdResponseType.response ? 'response' : 'release',
      };
}

enum UssdResponseType { response, release }
