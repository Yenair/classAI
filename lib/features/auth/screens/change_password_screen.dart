import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/core/services/auth_service.dart';
import 'package:classai/core/services/emergency_flush_service.dart';

/// Change password screen for forced password reset.
///
/// - Title "Set New Password".
/// - Two fields: New Password, Confirm New Password (matching, min 8 chars).
/// - Calls [AuthNotifier.changePassword] on submit.
/// - On success navigates to Dashboard.
/// - On error shows a snackbar with the error message.
///
/// Visual style matches the Google Stitch Vault Publisher card form.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  /// Stored reference for EmergencyFlush registration/unregistration.
  SaveCallback? _flushCallback;

  /// Cached reference to avoid `ref.read()` during disposal (Riverpod guard).
  late final EmergencyFlushService _emergencyFlush =
      ref.read(emergencyFlushServiceProvider);

  @override
  void initState() {
    super.initState();

    _flushCallback = () async {
      final newPassword = _newPasswordController.text;
      if (newPassword.isNotEmpty) {
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
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleChangePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(authProvider.notifier).changePassword(
            _newPasswordController.text,
          );

      if (!mounted) return;
      context.go('/');
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to change password. Please try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final authData = ref.watch(authProvider);

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
                    // ── Header icon ──────────────────────────────────
                    Icon(
                      Icons.lock_reset_rounded,
                      size: 56,
                      color: cs.primary,
                    ),
                    v16,
                    Text(
                      'Set New Password',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    v12,
                    Text(
                      'Your administrator has requested that you set a new password before continuing.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    v32,

                    // ── Form card ────────────────────────────────────
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
                          // ── Error banner from auth state ────────────
                          if (authData.errorMessage != null) ...[
                            _ErrorBanner(
                              message: authData.errorMessage!,
                              cs: cs,
                              onDismiss: () =>
                                  ref.read(authProvider.notifier).clearError(),
                            ),
                            v16,
                          ],

                          // ── New Password ─────────────────────────────
                          TextFormField(
                            controller: _newPasswordController,
                            obscureText: _obscureNewPassword,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'New Password',
                              prefixIcon: const Icon(Icons.lock_outlined),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureNewPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () => setState(() =>
                                    _obscureNewPassword = !_obscureNewPassword),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a new password';
                              }
                              if (value.length < 8) {
                                return 'Password must be at least 8 characters';
                              }
                              return null;
                            },
                          ),
                          v16,

                          // ── Confirm New Password ─────────────────────
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _handleChangePassword(),
                            decoration: InputDecoration(
                              labelText: 'Confirm New Password',
                              prefixIcon: const Icon(Icons.lock_outlined),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () => setState(() =>
                                    _obscureConfirmPassword =
                                        !_obscureConfirmPassword),
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

                          // ── Change Password button ───────────────────
                          SizedBox(
                            height: 56,
                            child: FilledButton(
                              onPressed:
                                  _isLoading ? null : _handleChangePassword,
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const Text(
                                      'Change Password',
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
