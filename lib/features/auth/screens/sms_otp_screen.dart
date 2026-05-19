import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// SMS OTP verification screen — currently stubbed.
///
/// SMS OTP functionality has been temporarily disabled.
/// This screen shows an informational demo matching the Stitch layout
/// and does not perform any SMS operations. Restore the full
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
    final cs = theme.colorScheme;

    const v12 = SizedBox(height: 12);
    const v24 = SizedBox(height: 24);
    const v48 = SizedBox(height: 48);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.surface.withValues(alpha: 0.6),
              cs.surfaceContainerLowest,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 32,
              vertical: 48,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Icon ─────────────────────────────────────────
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(
                      Icons.phone_android_rounded,
                      size: 40,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  v24,
                  // ── Title ────────────────────────────────────────
                  Text(
                    widget.purpose == 'activation'
                        ? 'Phone Verification'
                        : 'Recovery via SMS',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  v12,
                  // ── Primary description ──────────────────────────
                  Text(
                    'SMS OTP is currently unavailable.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
                  ),
                  v12,
                  // ── Secondary description ────────────────────────
                  Text(
                    'Please use email-based verification instead.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  v48,

                  // ── Go Back button ───────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Go Back',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
