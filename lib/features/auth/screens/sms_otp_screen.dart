import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// SMS OTP verification screen — currently stubbed.
///
/// SMS OTP functionality has been temporarily disabled.
/// This screen shows an informational placeholder and does
/// not perform any SMS operations. Restore the full
/// implementation when SMS OTP is re-enabled.
class SmsOtpScreen extends ConsumerStatefulWidget {
  final String? initialPhoneNumber;
  final Future<void> Function(String phoneNumber) onVerified;
  final String? smsMessageTemplate;
  final String? email;
  final String purpose;

  const SmsOtpScreen({
    super.key,
    this.initialPhoneNumber,
    required this.onVerified,
    this.smsMessageTemplate,
    this.email,
    this.purpose = 'activation',
  });

  @override
  ConsumerState<SmsOtpScreen> createState() => _SmsOtpScreenState();
}

class _SmsOtpScreenState extends ConsumerState<SmsOtpScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Verification'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.phone_android_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                widget.purpose == 'activation'
                    ? 'Phone Verification'
                    : 'Recovery via SMS',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                'SMS OTP is currently unavailable.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Please use email-based verification instead.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
