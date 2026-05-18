import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/core/services/auth_service.dart';
import 'package:classai/core/services/emergency_flush_service.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Maximum number of password recovery attempts per email per hour.
const int kMaxRecoveryAttemptsPerHour = 3;

/// Duration of the rate-limiting window for recovery attempts.
const Duration kRecoveryRateLimitDuration = Duration(hours: 1);

/// Teacher password recovery dialog.
///
/// The teacher enters their email, the recovery code provided by their admin,
/// and a new password. On success, the auth state transitions to authenticated.
///
/// Rate-limited to [kMaxRecoveryAttemptsPerHour] attempts per email per hour
/// using the [PendingRecoveryRequests] table.
class TeacherRecoveryDialog extends ConsumerStatefulWidget {
  const TeacherRecoveryDialog({super.key});

  @override
  ConsumerState<TeacherRecoveryDialog> createState() =>
      _TeacherRecoveryDialogState();
}

class _TeacherRecoveryDialogState
    extends ConsumerState<TeacherRecoveryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
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
      // Snapshot teacher recovery form fields before forced logout
      final email = _emailController.text;
      final code = _codeController.text;
      final newPassword = _newPasswordController.text;
      if (email.isNotEmpty || code.isNotEmpty || newPassword.isNotEmpty) {
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
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// Checks whether the given [email] has exceeded the rate limit for recovery
  /// attempts. Returns an error message if rate-limited, or `null` if allowed.
  ///
  /// Uses [PendingRecoveryRequestsDao] for type-safe queries instead of raw SQL.
  Future<String?> _checkRateLimit(String email) async {
    final db = ref.read(databaseProvider);
    final cutoff = DateTime.now().subtract(kRecoveryRateLimitDuration);

    final count = await db.pendingRecoveryRequestsDao
        .countRecentAttempts(email, cutoff);
    if (count >= kMaxRecoveryAttemptsPerHour) {
      return 'Too many recovery attempts. Please try again in 1 hour.';
    }
    return null;
  }

  /// Records a recovery attempt for the given [email] in the database.
  ///
  /// Uses [PendingRecoveryRequestsDao] for type-safe inserts instead of raw SQL.
  Future<void> _recordAttempt(String email) async {
    final db = ref.read(databaseProvider);
    await db.pendingRecoveryRequestsDao.recordAttempt(
      email: email,
      attemptedAt: DateTime.now(),
    );
  }

  Future<void> _handleRecover() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();

    // Rate-limit check before calling the server
    final rateLimitError = await _checkRateLimit(email);
    if (rateLimitError != null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = rateLimitError;
      });
      return;
    }

    // Record this attempt before the server call (counts toward the limit
    // regardless of outcome)
    await _recordAttempt(email);

    try {
      await ref.read(authProvider.notifier).recoverTeacherPassword(
            email: email,
            recoveryCode: _codeController.text.trim(),
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
        _errorMessage = 'Password recovery failed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Teacher Recovery'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter the recovery code provided by your school administrator.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 20),

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
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontSize: 13,
                          ),
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
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                      .hasMatch(value.trim())) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Recovery code field
              TextFormField(
                controller: _codeController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Recovery Code',
                  prefixIcon: Icon(Icons.vpn_key_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter the recovery code';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // New password
              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'New Password',
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
                    return 'Please enter a new password';
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
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _handleRecover(),
                decoration: InputDecoration(
                  labelText: 'Confirm New Password',
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
                    return 'Please confirm your new password';
                  }
                  if (value != _newPasswordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _handleRecover,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Reset Password'),
        ),
      ],
    );
  }
}
