
/// The type of deep link action parsed from a `classai://` URI.
enum DeepLinkType {
  /// Reset a teacher's password: `classai://reset-password?token=xxx`
  resetPassword,

  /// Activate a new account: `classai://activate?code=xxx`
  activate,

  /// Admin recovery OTP flow: `classai://admin-recovery?token=xxx`
  adminRecovery,
}

/// Represents a successfully parsed deep link.
class DeepLinkData {
  final DeepLinkType type;
  final Map<String, String> queryParameters;

  const DeepLinkData({
    required this.type,
    required this.queryParameters,
  });

  /// Convenience getters for known parameters.
  String? get token => queryParameters['token'];
  String? get code => queryParameters['code'];
}

/// Parses `classai://` deep links into structured data.
///
/// Supported URIs:
/// - `classai://reset-password?token=xxx`
/// - `classai://activate?code=xxx`
/// - `classai://admin-recovery?token=xxx`
class DeepLinkService {
  /// Attempt to parse [uri] as a ClassAI deep link.
  /// Returns `null` if the URI is not a recognised ClassAI deep link.
  static DeepLinkData? parse(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return null;

    // Must be classai:// scheme
    if (parsed.scheme != 'classai') return null;

    final host = parsed.host;
    final queryParams = parsed.queryParameters;

    switch (host) {
      case 'reset-password':
        if (queryParams.containsKey('token')) {
          return DeepLinkData(
            type: DeepLinkType.resetPassword,
            queryParameters: Map.unmodifiable(queryParams),
          );
        }
        return null;

      case 'activate':
        if (queryParams.containsKey('code')) {
          return DeepLinkData(
            type: DeepLinkType.activate,
            queryParameters: Map.unmodifiable(queryParams),
          );
        }
        return null;

      case 'admin-recovery':
        if (queryParams.containsKey('token')) {
          return DeepLinkData(
            type: DeepLinkType.adminRecovery,
            queryParameters: Map.unmodifiable(queryParams),
          );
        }
        return null;

      default:
        return null;
    }
  }
}
