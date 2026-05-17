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
