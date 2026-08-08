// lib/core/services/upgrade_request_service.dart
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_pkg;

/// Represents the possible outcomes of sending an upgrade request.
class UpgradeRequestResult {
  final bool success;
  final bool alreadyRequested;
  final bool failed;
  final String? message;

  const UpgradeRequestResult._({
    required this.success,
    required this.alreadyRequested,
    required this.failed,
    this.message,
  });

  /// The request was sent successfully (new unique request).
  factory UpgradeRequestResult.sent(String message) =>
      UpgradeRequestResult._(
        success: true,
        alreadyRequested: false,
        failed: false,
        message: message,
      );

  /// The teacher already requested an upgrade today.
  factory UpgradeRequestResult.alreadyRequestedToday() =>
      UpgradeRequestResult._(
        success: false,
        alreadyRequested: true,
        failed: false,
        message: 'Your request has already been sent to the school admin.',
      );

  /// The request failed due to network/offline/server error.
  factory UpgradeRequestResult.failed([String? msg]) =>
      UpgradeRequestResult._(
        success: false,
        alreadyRequested: false,
        failed: true,
        message: msg ??
            "Couldn't send your request — check your connection and try again.",
      );
}

/// Service for sending upgrade requests from a teacher to their school admin.
///
/// Calls the `request-upgrade` Edge Function with the teacher's JWT
/// (passed as a custom header) and the requested tier.
class UpgradeRequestService {
  const UpgradeRequestService();

  /// Send an upgrade request to the school admin.
  ///
  /// [accessToken] — the teacher's JWT from the auth service.
  /// [requestedTier] — the tier the teacher is requesting (e.g. "elite").
  ///
  /// Returns an [UpgradeRequestResult] with distinct outcomes:
  /// - [UpgradeRequestResult.sent] — new request created
  /// - [UpgradeRequestResult.alreadyRequestedToday] — duplicate for today
  /// - [UpgradeRequestResult.failed] — network/offline/server error
  Future<UpgradeRequestResult> sendUpgradeRequest({
    required String accessToken,
    required String requestedTier,
  }) async {
    try {
      if (accessToken.isEmpty) {
        return UpgradeRequestResult.failed(
          'Not authenticated. Please log in again.',
        );
      }

      final client = supabase_pkg.Supabase.instance.client;
      final response = await client.functions.invoke(
        'request-upgrade',
        headers: {
          'x-classai-jwt': accessToken,
        },
        body: {
          'requested_tier': requestedTier,
        },
      );

      final data = response.data as Map<String, dynamic>? ?? {};
      final httpStatus = response.status;

      // Successful HTTP 2xx with success flag
      if (httpStatus >= 200 && httpStatus < 300) {
        if (data['already_requested'] == true) {
          return UpgradeRequestResult.alreadyRequestedToday();
        }
        return UpgradeRequestResult.sent(
          data['message'] as String? ??
              'Upgrade request sent to school admin.',
        );
      }

      // Non-2xx response — server returned an error
      final errorMsg = data['error'] as String? ??
          'Server returned status $httpStatus';
      return UpgradeRequestResult.failed(errorMsg);
    } on supabase_pkg.FunctionException catch (e) {
      // Supabase function exception (non-2xx from edge function)
      final data = e.details as Map<String, dynamic>? ?? {};
      if (data['already_requested'] == true) {
        return UpgradeRequestResult.alreadyRequestedToday();
      }
      return UpgradeRequestResult.failed(
        data['error'] as String? ?? 'Server error',
      );
    } catch (e) {
      // Network error, offline, timeout, etc.
      return UpgradeRequestResult.failed();
    }
  }
}
