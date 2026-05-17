import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/constants/app_constants.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/core/services/auth_service.dart';
import 'package:classai/core/services/emergency_flush_service.dart';

/// Account activation screen for new admin or teacher accounts.
///
/// - Activation code, email, password fields.
/// - Role toggle (admin / teacher).
/// - Recovery email field (required for admin only).
/// - On success transitions to authenticated state.
class ActivationScreen extends ConsumerStatefulWidget {
  /// Optional activation code pre-filled via deep link.
  final String? initialCode;

  const ActivationScreen({super.key, this.initialCode});

  @override
  ConsumerState<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends ConsumerState<ActivationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _recoveryEmailController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isAdmin = false; // default to teacher
  bool _isLoading = false;
  String? _errorMessage;

  /// Cached device ID fetched once via [AppConstants.getDeviceId].
  String? _cachedDeviceId;

  /// Stored reference for EmergencyFlush registration/unregistration.
  SaveCallback? _flushCallback;

  /// Cached reference to avoid `ref.read()` during disposal (Riverpod guard).
  late final EmergencyFlushService _emergencyFlush =
      ref.read(emergencyFlushServiceProvider);

  @override
  void initState() {
    super.initState();

    // If deep link provided an activation code, pre-fill it
    if (widget.initialCode != null) {
      _codeController.text = widget.initialCode!;
    }

    _flushCallback = () async {
      // Snapshot all activation form fields before forced logout
      final code = _codeController.text;
      final email = _emailController.text;
      final password = _passwordController.text;
      final recoveryEmail = _recoveryEmailController.text;
      if (code.isNotEmpty ||
          email.isNotEmpty ||
          password.isNotEmpty ||
          recoveryEmail.isNotEmpty) {
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
    _codeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _recoveryEmailController.dispose();
    super.dispose();
  }

  Future<void> _handleActivate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Fetch device ID once and cache it
      _cachedDeviceId ??= await AppConstants.getDeviceId();

      await ref.read(authProvider.notifier).activateAccount(
            code: _codeController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
            deviceId: _cachedDeviceId!,
            isAdmin: _isAdmin,
            recoveryEmail: _isAdmin ? _recoveryEmailController.text.trim() : null,
          );

      if (!mounted) return;
      // On success, state machine transitions to authenticated.
      // Parent widget will detect this and navigate away.
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
        _errorMessage = 'Activation failed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activate Account'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Icon(
                  Icons.person_add_alt_1_rounded,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  'Activate Your Account',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Enter the activation code provided by ClassAI support or your school administrator.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),

                // Error banner
                if (_errorMessage != null) ...[
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
                            _errorMessage!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _errorMessage = null),
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

                // Activation code
                TextFormField(
                  controller: _codeController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Activation Code',
                    prefixIcon: Icon(Icons.qr_code_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your activation code';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Email
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
                    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                        .hasMatch(value.trim())) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Password
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
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
                      return 'Please enter a password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Confirm password
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please confirm your password';
                    }
                    if (value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Role toggle
                Text(
                  'Account Type',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Teacher'),
                      icon: Icon(Icons.person_rounded),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Admin'),
                      icon: Icon(Icons.admin_panel_settings_rounded),
                    ),
                  ],
                  selected: {_isAdmin},
                  onSelectionChanged: (value) {
                    setState(() => _isAdmin = value.first);
                  },
                ),
                const SizedBox(height: 16),

                // Recovery email (admin only)
                if (_isAdmin) ...[
                  TextFormField(
                    controller: _recoveryEmailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Recovery Email (Required for Admin)',
                      prefixIcon: Icon(Icons.contact_mail_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (_isAdmin &&
                          (value == null || value.trim().isEmpty)) {
                        return 'Recovery email is required for admin accounts';
                      }
                      if (value != null &&
                          value.isNotEmpty &&
                          !RegExp(r'^[^@]+@[^@]+\.[^@]+')
                              .hasMatch(value.trim())) {
                        return 'Please enter a valid recovery email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'This email will be used for password recovery. '
                    'A verification OTP will be sent to this address.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Submit button
                FilledButton(
                  onPressed: _isLoading ? null : _handleActivate,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Activate Account',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
