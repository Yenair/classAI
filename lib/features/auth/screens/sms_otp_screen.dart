import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/features/auth/screens/email_verification_dialog.dart';

/// SMS OTP verification screen — auto-redirects to email verification.
///
/// SMS OTP functionality has been disabled. This screen automatically
/// redirects to [EmailVerificationDialog] on first build.
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
  bool _redirected = false;

  @override
  Widget build(BuildContext context) {
    if (!_redirected) {
      _redirected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const EmailVerificationDialog(),
        ).then((_) {
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        });
      });
    }

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}
