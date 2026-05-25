import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';

/// A non-dismissible email verification dialog shown after login/signup
/// when the teacher's email has not yet been verified.
///
/// - Title: "Check Your Email"
/// - Message: Explains a verification code was sent.
/// - A 6-digit code input field.
/// - "Verify" button, "Resend Code" button (with 30-second cooldown), and "Cancel" button.
/// - Cannot be dismissed by tapping outside or pressing back.
class EmailVerificationDialog extends ConsumerStatefulWidget {
  const EmailVerificationDialog({super.key});

  @override
  ConsumerState<EmailVerificationDialog> createState() =>
      _EmailVerificationDialogState();
}

class _EmailVerificationDialogState
    extends ConsumerState<EmailVerificationDialog> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isVerifying = false;
  bool _isResending = false;
  bool _hasSentInitial = false;
  bool _hasEverAttemptedSend = false;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    // Clear any previous error message when the dialog opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasSentInitial) return;
      _hasSentInitial = true;
      ref.read(authProvider.notifier).clearError();
      _autoResend();
    });
  }

  void _autoResend() {
    // Only send automatically once per dialog session to prevent retry loops
    // when the server returns errors.
    if (_hasEverAttemptedSend) return;
    _hasEverAttemptedSend = true;
    _resend();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isVerifying = true);

    try {
      await ref
          .read(authProvider.notifier)
          .verifyEmailCode(_codeController.text.trim());

      if (!mounted) return;

      // If the state changed to authenticated, the dialog will be closed
      // by the parent widget that watches the auth state.
      final authState = ref.read(authProvider).state;
      if (authState == AuthState.emailVerificationRequired) {
        // Still in verification state — an error was likely set.
        setState(() => _isVerifying = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  Future<void> _resend() async {
    // Don't resend if cooldown is active or already sending
    if (_resendCooldown > 0 || _isResending) return;

    setState(() => _isResending = true);

    try {
      await ref.read(authProvider.notifier).resendVerificationCode();

      if (!mounted) return;

      final errorMessage = ref.read(authProvider).errorMessage;
      final resendSucceeded = errorMessage == null || errorMessage.isEmpty;

      if (resendSucceeded) {
        setState(() {
          _resendCooldown = 30;
        });

        _cooldownTimer?.cancel();
        _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          setState(() {
            _resendCooldown--;
            if (_resendCooldown <= 0) {
              _cooldownTimer?.cancel();
              _cooldownTimer = null;
            }
          });
        });
      } else {
        // On failure, set a minimum cooldown to prevent error flood
        setState(() {
          _resendCooldown = 5; // 5 second minimum before retry
        });

        _cooldownTimer?.cancel();
        _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          setState(() {
            _resendCooldown--;
            if (_resendCooldown <= 0) {
              _cooldownTimer?.cancel();
              _cooldownTimer = null;
            }
          });
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  Future<void> _cancel() async {
    // Log the user out, which transitions to onlineLoginRequired state.
    // The parent listener in LoginScreen will detect the state change
    // and pop the dialog, showing the login screen immediately.
    await ref.read(authProvider.notifier).manualLogout();
  }

  @override
  Widget build(BuildContext context) {
    final authData = ref.watch(authProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // Prevent dismissal via back button or tapping outside
        if (!didPop) {
          // User tried to dismiss via back button - ignore it
          return;
        }
      },
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: cs.surfaceContainerLowest,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header icon ─────────────────────────────────────
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.email_outlined,
                    size: 28,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Title ───────────────────────────────────────────
              Text(
                'Check Your Email',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 10),

              // ── Message ─────────────────────────────────────────
              Text(
                'A verification code has been sent to your email address. '
                'Please enter it below.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // ── Error banner ────────────────────────────────────
              if (authData.errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: cs.onErrorContainer,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          authData.errorMessage!,
                          style: TextStyle(
                            color: cs.onErrorContainer,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Code input ─────────────────────────────────────
              TextFormField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 8,
                  color: cs.onSurface,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  labelText: 'Verification Code',
                  hintText: '000000',
                  helperText: 'Enter the 6-digit code sent to your email',
                  helperMaxLines: 2,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter the verification code';
                  }
                  if (!RegExp(r'^\d{6}$').hasMatch(value.trim())) {
                    return 'Please enter a valid 6-digit code';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 20),

              // ── Verify button ──────────────────────────────────
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _isVerifying ? null : _verify,
                  child: _isVerifying
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Resend Code button ─────────────────────────────
              SizedBox(
                height: 44,
                child: ValueListenableBuilder<int>(
                  valueListenable: ValueNotifier(_resendCooldown),
                  builder: (context, cooldown, child) {
                    return TextButton(
                      onPressed: (_isResending || _isVerifying || cooldown > 0)
                          ? null
                          : _resend,
                      child: cooldown > 0
                          ? Text(
                              'Resend in ${cooldown}s',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurfaceVariant,
                              ),
                            )
                          : _isResending
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text(
                                  'Resend Code',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),

              // ── Cancel button ──────────────────────────────────
              SizedBox(
                height: 44,
                child: TextButton(
                  onPressed: _isVerifying ? null : _cancel,
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: cs.error,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
