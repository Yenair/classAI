import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/constants/app_constants.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/core/services/emergency_flush_service.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/auth/screens/signup_screen.dart';
import 'package:classai/features/auth/screens/change_password_screen.dart';
import 'package:classai/features/auth/screens/forgot_password_dialog.dart';
import 'package:classai/features/auth/screens/admin_recovery_screen.dart';
import 'package:classai/features/auth/screens/teacher_recovery_dialog.dart';
import 'package:classai/features/auth/screens/email_verification_dialog.dart';

/// Material Design login screen with email/password fields,
/// forgot password links, account activation, error states, and loading.
///
/// Layout and styling match the Google Stitch Vault Publisher design:
/// centered surface-card on a surface background, 56 px touch targets,
/// pill-shaped primary button, and low-prominence secondary links.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoggingIn = false;

  /// Cached device ID fetched once via [AppConstants.getDeviceId].
  String? _cachedDeviceId;

  /// Stored reference for EmergencyFlush registration/unregistration.
  /// Must be the same object for both register and unregister calls.
  SaveCallback? _flushCallback;

  /// Keeps the auth listener alive without re-registering it on rebuilds.
  ProviderSubscription<AuthStateData>? _authStateSubscription;

  /// Cached reference to avoid `ref.read()` during disposal (Riverpod guard).
  late final EmergencyFlushService _emergencyFlush =
      ref.read(emergencyFlushServiceProvider);

  @override
  void initState() {
    super.initState();
    // Register an emergency save callback that snapshots form fields
    // so unsaved input is captured before forced logout.
    _flushCallback = () async {
      final email = _emailController.text;
      final password = _passwordController.text;
      if (email.isNotEmpty || password.isNotEmpty) {
        // In production, write to a dead-letter queue or local draft store.
      }
    };
    _emergencyFlush.register(_flushCallback!);

    _authStateSubscription = ref.listenManual<AuthStateData>(
      authProvider,
      (previous, next) {
        if (previous?.state != AuthState.emailVerificationRequired &&
            next.state == AuthState.emailVerificationRequired &&
            mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const EmailVerificationDialog(),
          );
        }

        if (previous?.state == AuthState.emailVerificationRequired &&
            (next.state == AuthState.authenticated ||
                next.state == AuthState.uninitialized ||
                next.state == AuthState.onlineLoginRequired) &&
            mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      },
    );
  }

  @override
  void dispose() {
    _authStateSubscription?.close();
    if (_flushCallback != null) {
      _emergencyFlush.unregister(_flushCallback!);
    }
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoggingIn = true);

    try {
      ref.read(authProvider.notifier).clearError();

      try {
        _cachedDeviceId ??= await AppConstants.getDeviceId();
      } catch (_) {
        _cachedDeviceId ??= _generateFallbackDeviceId();
      }

      await ref.read(authProvider.notifier).loginOnline(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            deviceId: _cachedDeviceId!,
          );

      if (!mounted) return;
      final authState = ref.read(authProvider).state;
      if (authState == AuthState.forcePasswordResetRequired) {
        ref.read(authProvider.notifier).clearError();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ChangePasswordScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ref.read(authProvider.notifier).setErrorMessage(
              'An unexpected error occurred. Please try again.',
            );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoggingIn = false);
      }
    }
  }

  String _generateFallbackDeviceId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = now ^ (now << 21);
    return 'fallback-${random.toRadixString(16).padLeft(12, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final authData = ref.watch(authProvider);

    // ── Watch for emailVerificationRequired state ─────────────────
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // ── Spacing scale (Stitch-like) ───────────────────────────────
    const v8 = SizedBox(height: 8);
    const v16 = SizedBox(height: 16);
    const v24 = SizedBox(height: 24);

    return Scaffold(
      body: Container(
        // Stitch background: gradient-like surface / surface-container-low blend
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
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header: school icon + title ─────────────────────
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.school_rounded,
                      size: 32,
                      color: cs.primary,
                    ),
                  ),
                  v16,
                  Text(
                    'ClassAI',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: cs.onSurface,
                    ),
                  ),
                  v8,
                  Text(
                    'Sign in to ClassAI',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  v24,

                  // ── Form card ──────────────────────────────────────
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                        decoration: BoxDecoration(
                          color:
                              cs.surfaceContainerLowest.withValues(alpha: 0.85),
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
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ── Error banner ─────────────────────────────
                              if (authData.errorMessage != null) ...[
                                _ErrorBanner(
                                  message: authData.errorMessage!,
                                  cs: cs,
                                  onDismiss: () => ref
                                      .read(authProvider.notifier)
                                      .clearError(),
                                ),
                                v16,
                              ],

                              // ── Account deactivated notice ───────────────
                              if (authData.state ==
                                  AuthState.accountDeactivated) ...[
                                _DeactivatedNotice(cs: cs),
                                v16,
                              ],

                              // ── Email field ─────────────────────────────
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
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
                              v16,

                              // ── Password field ──────────────────────────
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _handleLogin(),
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outlined),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your password';
                                  }
                                  if (value.length < 6) {
                                    return 'Password must be at least 6 characters';
                                  }
                                  return null;
                                },
                              ),
                              v8,

                              // ── Sign In button ──────────────────────────
                              SizedBox(
                                height: 56,
                                child: FilledButton(
                                  onPressed: _isLoggingIn ? null : _handleLogin,
                                  child: _isLoggingIn
                                      ? SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: cs.onPrimary,
                                          ),
                                        )
                                      : const Text(
                                          'Sign In',
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

                  v24,

                  // ── Secondary links ─────────────────────────────
                  _SecondaryLink(
                    label: 'Forgot Password?',
                    onPressed: _isLoggingIn ? null : _showForgotPasswordFlow,
                    cs: cs,
                  ),
                  const SizedBox(height: 8),
                  _SecondaryLink(
                    label: 'Create a School Account',
                    onPressed: _isLoggingIn ? null : _showCreateAccountFlow,
                    cs: cs,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Role-branching forgot password flow.
  Future<void> _showForgotPasswordFlow() async {
    final role = await ForgotPasswordDialog.show(context);
    if (!mounted || role == null) return;

    if (role == 'admin') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const AdminRecoveryScreen(),
        ),
      );
    } else {
      await showDialog(
        context: context,
        builder: (_) => const TeacherRecoveryDialog(),
      );
    }
  }

  /// Navigate to the signup screen.
  Future<void> _showCreateAccountFlow() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SignupScreen(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stitch-derived helper widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Inline error banner matching Stitch error-token colours.
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
            child: SelectableText(
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

/// Account-deactivated notice card.
class _DeactivatedNotice extends StatelessWidget {
  const _DeactivatedNotice({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: cs.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Account Deactivated',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.error,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Please contact your school administrator to reactivate your account.',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Low-prominence text link used for secondary actions below the form.
class _SecondaryLink extends StatelessWidget {
  const _SecondaryLink({
    required this.label,
    this.onPressed,
    required this.cs,
  });

  final String label;
  final VoidCallback? onPressed;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 8),
      ),
      child: Text(label),
    );
  }
}
