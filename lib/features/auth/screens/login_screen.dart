import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/constants/app_constants.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/core/services/emergency_flush_service.dart';
import 'package:classai/core/theme/app_theme.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/auth/screens/signup_screen.dart';
import 'package:classai/features/auth/screens/change_password_screen.dart';
import 'package:classai/features/auth/screens/forgot_password_dialog.dart';
import 'package:classai/features/auth/screens/admin_recovery_screen.dart';
import 'package:classai/features/auth/screens/teacher_recovery_dialog.dart';
import 'package:classai/features/auth/screens/email_verification_dialog.dart';

/// Login screen redesigned to match the Google Stitch design HTML.
///
/// Layout:
/// - Tablet+: Two-column layout — left hero/branding area, right login card
/// - Phone: Single-column centered login card
///
/// All business logic (auth provider, form validation, EmergencyFlush,
/// navigation to signup/forgot-password) is preserved unchanged.
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
  SaveCallback? _flushCallback;

  /// Keeps the auth listener alive without re-registering it on rebuilds.
  ProviderSubscription<AuthStateData>? _authStateSubscription;

  /// Cached reference to avoid `ref.read()` during disposal (Riverpod guard).
  late final EmergencyFlushService _emergencyFlush =
      ref.read(emergencyFlushServiceProvider);

  @override
  void initState() {
    super.initState();
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 768;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Left Side: Hero/Branding Area (Tablet+) ─────────────
            if (isTablet)
              Expanded(
                child: _HeroBranding(cs: cs),
              ),

            // ── Right Side: Login Container ─────────────────────────
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(
                    isTablet
                        ? AppTheme.spacingMarginTablet
                        : AppTheme.spacingMarginMobile,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: _LoginCard(
                      formKey: _formKey,
                      emailController: _emailController,
                      passwordController: _passwordController,
                      obscurePassword: _obscurePassword,
                      isLoggingIn: _isLoggingIn,
                      authData: authData,
                      cs: cs,
                      theme: theme,
                      onToggleObscure: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      onLogin: _handleLogin,
                      onForgotPassword: _showForgotPasswordFlow,
                      onActivate: _showCreateAccountFlow,
                      onDismissError: () =>
                          ref.read(authProvider.notifier).clearError(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  Future<void> _showCreateAccountFlow() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SignupScreen(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  HERO BRANDING AREA (Tablet+)
// ═══════════════════════════════════════════════════════════════════════════

class _HeroBranding extends StatelessWidget {
  const _HeroBranding({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: cs.surfaceContainerLow,
      child: Stack(
        children: [
          // Overlay tint
          Positioned.fill(
            child: Container(color: cs.primary.withValues(alpha: 0.05)),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Empowering Nigerian\nEducation.',
                  style: Theme.of(context)
                      .textTheme
                      .displayLarge
                      ?.copyWith(color: cs.primary),
                ),
                const SizedBox(height: 24),
                Text(
                  'Your trusted academic partner. Manage classrooms, track attendance, and stream lessons seamlessly.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
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

// ═══════════════════════════════════════════════════════════════════════════
//  LOGIN CARD
// ═══════════════════════════════════════════════════════════════════════════

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.isLoggingIn,
    required this.authData,
    required this.cs,
    required this.theme,
    required this.onToggleObscure,
    required this.onLogin,
    required this.onForgotPassword,
    required this.onActivate,
    required this.onDismissError,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool isLoggingIn;
  final AuthStateData authData;
  final ColorScheme cs;
  final ThemeData theme;
  final VoidCallback onToggleObscure;
  final VoidCallback onLogin;
  final VoidCallback onForgotPassword;
  final VoidCallback onActivate;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.onSurface.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Logo Header ───────────────────────────────────────────
          Center(
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                  ),
                  child: Icon(
                    Icons.school_rounded,
                    size: 32,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'ClassAI',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Welcome back, Educator.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Login Form ───────────────────────────────────────────
          Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Error banner ───────────────────────────────────
                if (authData.errorMessage != null) ...[
                  _ErrorBanner(
                    message: authData.errorMessage!,
                    cs: cs,
                    onDismiss: onDismissError,
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Account deactivated notice ─────────────────────
                if (authData.state == AuthState.accountDeactivated) ...[
                  _DeactivatedNotice(cs: cs),
                  const SizedBox(height: 16),
                ],

                // ── Email field ────────────────────────────────────
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
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
                const SizedBox(height: 16),

                // ── Password field ─────────────────────────────────
                TextFormField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => onLogin(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: onToggleObscure,
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
                const SizedBox(height: 16),

                // ── Forgot Password row ────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: isLoggingIn ? null : onForgotPassword,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Forgot Password?',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // ── Sign In button ─────────────────────────────────
                SizedBox(
                  height: AppTheme.touchTarget,
                  child: FilledButton(
                    onPressed: isLoggingIn ? null : onLogin,
                    child: isLoggingIn
                        ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: cs.onPrimary,
                            ),
                          )
                        : Text(
                            'Sign In',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Recovery Info Box ────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: cs.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.5,
                      ),
                      children: [
                        TextSpan(
                          text: 'Teacher Recovery: ',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const TextSpan(
                          text:
                              'Please contact your institutional Admin for password resets.\n',
                        ),
                        TextSpan(
                          text: 'Admin Recovery: ',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const TextSpan(
                          text:
                              "Use the 'Forgot Password' link to get an OTP via email.",
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ── Create a School Account Link ─────────────────────────
          Container(
            padding: const EdgeInsets.only(top: 24),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'New to ClassAI?',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: isLoggingIn ? null : onActivate,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Create a School Account',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward,
                          size: 16,
                          color: cs.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ERROR BANNER
// ═══════════════════════════════════════════════════════════════════════════

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
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
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
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
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
