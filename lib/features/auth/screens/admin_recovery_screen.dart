import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/core/services/auth_service.dart';
import 'package:classai/core/services/emergency_flush_service.dart';

/// Multi-step admin recovery flow.
///
/// Step 1: Admin enters email → OTP sent to recovery email.
/// Step 2: Admin enters OTP + new password → password reset, school key re-wrapped.
///
/// Triggered from the "Forgot Password?" dialog when the user selects "Admin".
///
/// Visual style matches the Stitch Vault Publisher card form.
class AdminRecoveryScreen extends ConsumerStatefulWidget {
  const AdminRecoveryScreen({super.key});

  @override
  ConsumerState<AdminRecoveryScreen> createState() =>
      _AdminRecoveryScreenState();
}

class _AdminRecoveryScreenState extends ConsumerState<AdminRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  bool _otpSent = false;
  DateTime? _otpExpiry;
  String? _errorMessage;

  /// Stored reference for EmergencyFlush registration/unregistration.
  SaveCallback? _flushCallback;

  /// Cached reference to avoid `ref.read()` during disposal (Riverpod guard).
  late final EmergencyFlushService _emergencyFlush =
      ref.read(emergencyFlushServiceProvider);

  @override
  void initState() {
    super.initState();
    _flushCallback = () async {
      final email = _emailController.text;
      final otp = _otpController.text;
      final newPassword = _newPasswordController.text;
      if (email.isNotEmpty || otp.isNotEmpty || newPassword.isNotEmpty) {
        // In production, write to a dead-letter queue or local draft store.
      }
    };
    _emergencyFlush.register(_flushCallback!);
  }

  @override
  void dispose() {
    if (_flushCallback != null) {
      _emergencyFlush.unregister(_flushCallback!);
    }
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await ref
          .read(authProvider.notifier)
          .requestAdminOtp(_emailController.text.trim());

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _otpSent = true;
        _otpExpiry = result.otpExpiry;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'OTP sent. If you don\'t receive it within a few minutes, '
              'please check your spam folder.',
            ),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: () {},
            ),
          ),
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Network error. Please try again.';
      });
    }
  }

  Future<void> _verifyOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authProvider.notifier).verifyAdminOtp(
            email: _emailController.text.trim(),
            otp: _otpController.text.trim(),
            newPassword: _newPasswordController.text,
          );

      if (!mounted) return;
      Navigator.of(context).pop();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Verification failed. Please try again.';
      });
    }
  }

  String _formatExpiry(DateTime expiry) {
    final remaining = expiry.difference(DateTime.now());
    if (remaining.isNegative) return 'Expired';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    const v12 = SizedBox(height: 12);
    const v16 = SizedBox(height: 16);
    const v24 = SizedBox(height: 24);
    const v32 = SizedBox(height: 32);

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
              horizontal: 24,
              vertical: 40,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Header icon ─────────────────────────────────
                    Icon(
                      Icons.admin_panel_settings_rounded,
                      size: 56,
                      color: cs.primary,
                    ),
                    v16,
                    Text(
                      _otpSent ? 'Enter Recovery Code' : 'Admin Recovery',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    v12,
                    Text(
                      _otpSent
                          ? 'Enter the OTP sent to your recovery email and choose a new password.'
                          : 'Enter your email address. An OTP will be sent to your recovery email on file.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    v32,

                    // ── Form card ───────────────────────────────────
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.45),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: cs.onSurface.withValues(alpha: 0.05),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Error banner ─────────────────────────────
                          if (_errorMessage != null) ...[
                            _ErrorBanner(
                              message: _errorMessage!,
                              cs: cs,
                              onDismiss: () =>
                                  setState(() => _errorMessage = null),
                            ),
                            v16,
                          ],

                          // ── Email (disabled after OTP sent) ──────────
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: _otpSent
                                ? TextInputAction.next
                                : TextInputAction.done,
                            enabled: !_otpSent,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                                  .hasMatch(value.trim())) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),

                          // ── Step-2 fields (shown after OTP sent) ─────
                          if (_otpSent) ...[
                            v16,

                            // OTP expiry countdown
                            if (_otpExpiry != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  'OTP expires in ${_formatExpiry(_otpExpiry!)}',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                    color: _otpExpiry!.isBefore(DateTime.now())
                                        ? cs.error
                                        : cs.primary,
                                  ),
                                ),
                              ),

                            // OTP Code
                            TextFormField(
                              controller: _otpController,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              maxLength: 6,
                              decoration: const InputDecoration(
                                labelText: 'OTP Code',
                                prefixIcon: Icon(Icons.pin_outlined),
                                counterText: '',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter the OTP';
                                }
                                if (value.trim().length != 6) {
                                  return 'OTP must be 6 digits';
                                }
                                return null;
                              },
                            ),
                            v16,

                            // New Password
                            TextFormField(
                              controller: _newPasswordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'New Password',
                                prefixIcon: const Icon(Icons.lock_outlined),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  onPressed: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a new password';
                                }
                                if (value.length < 6) {
                                  return 'Password must be at least 6 characters';
                                }
                                return null;
                              },
                            ),
                            v16,

                            // Confirm New Password
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: _obscureConfirm,
                              textInputAction: TextInputAction.done,
                              decoration: InputDecoration(
                                labelText: 'Confirm New Password',
                                prefixIcon: const Icon(Icons.lock_outlined),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  onPressed: () => setState(
                                      () => _obscureConfirm = !_obscureConfirm),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please confirm your new password';
                                }
                                if (value != _newPasswordController.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                            ),
                            v24,

                            // ── Reset Password button ──────────────────
                            SizedBox(
                              height: 56,
                              child: FilledButton(
                                onPressed: _isLoading ? null : _verifyOtp,
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : const Text(
                                        'Reset Password',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                              ),
                            ),
                            v12,

                            // ── Resend OTP link ───────────────────────
                            Center(
                              child: TextButton(
                                onPressed: _isLoading
                                    ? null
                                    : () => setState(() {
                                          _otpSent = false;
                                          _errorMessage = null;
                                        }),
                                child: const Text(
                                    'Resend OTP (enter email again)'),
                              ),
                            ),
                          ] else ...[
                            // ── Step 1: Send OTP button ────────────────
                            SizedBox(
                              height: 56,
                              child: FilledButton(
                                onPressed: _isLoading ? null : _requestOtp,
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : const Text(
                                        'Send OTP',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.cs,
    required this.onDismiss,
  });

  final String message;
  final ColorScheme cs;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            color: cs.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: cs.onErrorContainer,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onDismiss,
            child: Icon(
              Icons.close,
              size: 18,
              color: cs.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}
