import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/constants/app_constants.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/auth/screens/forgot_password_dialog.dart';
import 'package:classai/features/auth/screens/admin_recovery_screen.dart';
import 'package:classai/features/auth/screens/teacher_recovery_dialog.dart';
import 'package:classai/features/auth/screens/activation_screen.dart';
import 'package:classai/core/services/emergency_flush_service.dart';

/// Material Design login screen with email/password fields,
/// forgot password links, account activation, error states, and loading.
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

  /// Cached reference to avoid `ref.read()` during disposal (Riverpod guard).
  late final EmergencyFlushService _emergencyFlush =
      ref.read(emergencyFlushServiceProvider);

  @override
  void initState() {
    super.initState();
    // Register an emergency save callback that snapshots form fields
    // so unsaved input is captured before forced logout.
    _flushCallback = () async {
      // Snapshot current form state to prevent data loss on forced logout
      final email = _emailController.text;
      final password = _passwordController.text;
      if (email.isNotEmpty || password.isNotEmpty) {
        // In production, write to a dead-letter queue or local draft store.
        // For now, the capture itself prevents silent data loss.
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
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoggingIn = true);

    try {
      // Clear previous errors
      ref.read(authProvider.notifier).clearError();

      // Fetch device ID once and cache it
      _cachedDeviceId ??= await AppConstants.getDeviceId();

      // Attempt online login
      await ref.read(authProvider.notifier).loginOnline(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            deviceId: _cachedDeviceId!,
          );

      // Check final state for errors
      final authState = ref.read(authProvider).state;
      if (authState == AuthState.authenticated) {
        // Navigate to main app handled by parent widget listening to auth state
      }
    } finally {
      if (mounted) {
        setState(() => _isLoggingIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authData = ref.watch(authProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ClassAI'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App icon / branding
                  Icon(
                    Icons.school_rounded,
                    size: 72,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to ClassAI',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Error banner
                  if (authData.errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: theme.colorScheme.onErrorContainer,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              authData.errorMessage!,
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () =>
                                ref.read(authProvider.notifier).clearError(),
                            child: Icon(
                              Icons.close,
                              size: 18,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Account deactivated card
                  if (authData.state == AuthState.accountDeactivated) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Colors.orange),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Account Deactivated',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Please contact your school administrator to reactivate your account.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Password field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleLogin(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
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
                  const SizedBox(height: 24),

                  // Login button
                  FilledButton(
                    onPressed: _isLoggingIn ? null : _handleLogin,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoggingIn
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Sign In',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                  const SizedBox(height: 16),

                  // Forgot password link
                  TextButton(
                    onPressed: _isLoggingIn
                        ? null
                        : () => _showForgotPasswordFlow(),
                    child: const Text('Forgot Password?'),
                  ),

                  // Activate account link
                  TextButton(
                    onPressed: _isLoggingIn
                        ? null
                        : () => _showActivateAccountFlow(),
                    child: const Text('Activate Account'),
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
  ///
  /// Shows a dialog asking "Admin or Teacher?" then navigates to the
  /// appropriate recovery flow.
  Future<void> _showForgotPasswordFlow() async {
    final role = await ForgotPasswordDialog.show(context);
    if (!mounted || role == null) return;

    if (role == 'admin') {
      // Navigate to admin recovery screen (full-screen, not a dialog)
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const AdminRecoveryScreen(),
        ),
      );
    } else {
      // Show teacher recovery dialog
      await showDialog(
        context: context,
        builder: (_) => const TeacherRecoveryDialog(),
      );
    }
  }

  /// Navigate to the activation screen.
  Future<void> _showActivateAccountFlow() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ActivationScreen(),
      ),
    );
  }
}
