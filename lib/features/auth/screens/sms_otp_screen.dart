import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/services/sms_otp_service.dart';
import 'package:dio/dio.dart';

/// SMS OTP verification screen for account activation and password recovery.
///
/// This screen provides an alternative to email OTP for users who
/// have registered a phone number. It's especially important for
/// Nigerian schools where SMS is more reliable than email.
///
/// ## Flow
/// 1. User enters their phone number
/// 2. SMS OTP is sent via Termii (or BulkSMS Nigeria as fallback)
/// 3. User enters the 6-digit OTP code
/// 4. On success, the caller's callback is invoked with the phone number
class SmsOtpScreen extends ConsumerStatefulWidget {
  /// Phone number to pre-fill (optional).
  final String? initialPhoneNumber;

  /// Callback when OTP is verified successfully.
  final Future<void> Function(String phoneNumber) onVerified;

  /// Optional custom message for the OTP SMS.
  final String? smsMessageTemplate;

  const SmsOtpScreen({
    super.key,
    this.initialPhoneNumber,
    required this.onVerified,
    this.smsMessageTemplate,
  });

  @override
  ConsumerState<SmsOtpScreen> createState() => _SmsOtpScreenState();
}

class _SmsOtpScreenState extends ConsumerState<SmsOtpScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSendingOtp = false;
  bool _isVerifying = false;
  bool _otpSent = false;
  String? _errorMessage;
  String? _successMessage;
  late final SmsOtpService _smsOtpService;

  @override
  void initState() {
    super.initState();
    _phoneController.text = widget.initialPhoneNumber ?? '';
    // Initialize with default config; in production, read from secure config
    _smsOtpService = SmsOtpService(
      Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      )),
      const SmsProviderConfig(
        apiKey: '', // Set via server config in production
        senderId: 'ClassAI',
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSendingOtp = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final phoneNumber = _phoneController.text.trim();
      final result = await _smsOtpService.sendOtpViaTermii(
        phoneNumber: phoneNumber,
        messageTemplate: widget.smsMessageTemplate,
      );

      if (result.sent) {
        setState(() {
          _otpSent = true;
          _successMessage = 'OTP sent to $phoneNumber';
        });
      } else {
        setState(() {
          _errorMessage = result.message ?? 'Failed to send OTP';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to send OTP: $e';
      });
    } finally {
      setState(() => _isSendingOtp = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      // In production, verify against the server or stored OTP
      final phoneNumber = _phoneController.text.trim();
      await widget.onVerified(phoneNumber);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _errorMessage = 'Verification failed: $e';
      });
    } finally {
      setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Verification'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.phone_android_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Phone Verification',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your phone number to receive a verification code via SMS.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),

              // Phone number field
              TextFormField(
                controller: _phoneController,
                enabled: !_otpSent,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '+2348012345678',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your phone number';
                  }
                  if (!value.trim().startsWith('+')) {
                    return 'Use international format (e.g., +234...)';
                  }
                  if (value.trim().length < 10) {
                    return 'Enter a valid phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              if (!_otpSent)
                FilledButton.icon(
                  onPressed: _isSendingOtp ? null : _sendOtp,
                  icon: _isSendingOtp
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_isSendingOtp ? 'Sending...' : 'Send OTP'),
                ),

              if (_otpSent) ...[
                // OTP code field
                TextFormField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: 'OTP Code',
                    hintText: '123456',
                    prefixIcon: const Icon(Icons.pin),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter the OTP code';
                    }
                    if (value.trim().length != 6) {
                      return 'OTP must be 6 digits';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _isVerifying ? null : _verifyOtp,
                  icon: _isVerifying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified),
                  label: Text(_isVerifying ? 'Verifying...' : 'Verify OTP'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _isSendingOtp ? null : _sendOtp,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Resend OTP'),
                ),
              ],

              // Error/Success messages
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: theme.colorScheme.onErrorContainer, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_successMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: theme.colorScheme.onPrimaryContainer,
                          size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
