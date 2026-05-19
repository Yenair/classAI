import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/constants/app_constants.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/core/services/auth_service.dart';
import 'package:classai/core/services/emergency_flush_service.dart';

/// Signup screen for creating a new school account.
///
/// - School Name, Short Code (auto-generated, read-only), Admin Email,
///   Admin Password, Recovery Email (optional).
/// - On success transitions to authenticated state (Dashboard).
///
/// Layout and spacing match the Google Stitch Vault Publisher form card:
/// surface-container-low card on gradient background, 56 px buttons,
/// consistent 16-sp vertical gaps between fields.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _schoolNameController = TextEditingController();
  final _shortCodeController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _adminPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _recoveryEmailController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMessage;

  /// Cached device ID fetched once via [AppConstants.getDeviceId].
  String? _cachedDeviceId;

  /// Stored reference for EmergencyFlush registration/unregistration.
  SaveCallback? _flushCallback;

  /// Cached reference to avoid `ref.read()` during disposal (Riverpod guard).
  late final EmergencyFlushService _emergencyFlush =
      ref.read(emergencyFlushServiceProvider);

  /// Generates a short code from the school name (uppercase, max 6 chars).
  String _generateShortCode(String schoolName) {
    final cleaned =
        schoolName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    return cleaned.length > 6 ? cleaned.substring(0, 6) : cleaned;
  }

  @override
  void initState() {
    super.initState();

    // Auto-generate short code when school name changes
    _schoolNameController.addListener(() {
      final name = _schoolNameController.text;
      if (name.isNotEmpty) {
        _shortCodeController.text = _generateShortCode(name);
      } else {
        _shortCodeController.text = '';
      }
    });

    _flushCallback = () async {
      final schoolName = _schoolNameController.text;
      final email = _adminEmailController.text;
      final password = _adminPasswordController.text;
      final recoveryEmail = _recoveryEmailController.text;
      if (schoolName.isNotEmpty ||
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
    _schoolNameController.dispose();
    _shortCodeController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    _confirmPasswordController.dispose();
    _recoveryEmailController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _cachedDeviceId ??= await AppConstants.getDeviceId();

      await ref.read(authProvider.notifier).signup(
            schoolName: _schoolNameController.text.trim(),
            adminEmail: _adminEmailController.text.trim(),
            adminPassword: _adminPasswordController.text,
            recoveryEmail: _recoveryEmailController.text.trim().isEmpty
                ? null
                : _recoveryEmailController.text.trim(),
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
        _errorMessage = 'Signup failed. $e';
      });
    }
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
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ────────────────────────────────────────
                  Icon(
                    Icons.groups_rounded,
                    size: 56,
                    color: cs.primary,
                  ),
                  v16,
                  Text(
                    'Create School Account',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  v12,
                  Text(
                    'Register your school to get started with ClassAI.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ── Form card ─────────────────────────────────────
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
                    child: Form(
                      key: _formKey,
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

                          // ── School Name ──────────────────────────────
                          TextFormField(
                            controller: _schoolNameController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'School Name',
                              prefixIcon: Icon(Icons.business_rounded),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your school name';
                              }
                              if (value.trim().length < 3) {
                                return 'School name must be at least 3 characters';
                              }
                              return null;
                            },
                          ),
                          v16,

                          // ── Short Code (auto, read-only) ────────────
                          TextFormField(
                            controller: _shortCodeController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Short Code',
                              prefixIcon: Icon(Icons.qr_code_rounded),
                              helperText: 'Auto-generated from school name',
                            ),
                          ),
                          v16,

                          // ── Admin Email ─────────────────────────────
                          TextFormField(
                            controller: _adminEmailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Admin Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter the admin email';
                              }
                              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                                  .hasMatch(value.trim())) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                          v16,

                          // ── Admin Password ───────────────────────────
                          TextFormField(
                            controller: _adminPasswordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Admin Password',
                              prefixIcon: const Icon(Icons.lock_outlined),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a password';
                              }
                              if (value.length < 8) {
                                return 'Password must be at least 8 characters';
                              }
                              return null;
                            },
                          ),
                          v16,

                          // ── Confirm Password ─────────────────────────
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirm,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Confirm Password',
                              prefixIcon: const Icon(Icons.lock_outlined),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirm
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please confirm your password';
                              }
                              if (value != _adminPasswordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          v16,

                          // ── Recovery Email ───────────────────────────
                          TextFormField(
                            controller: _recoveryEmailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Recovery Email (optional)',
                              prefixIcon: Icon(Icons.contact_mail_outlined),
                            ),
                            validator: (value) {
                              if (value != null &&
                                  value.isNotEmpty &&
                                  !RegExp(r'^[^@]+@[^@]+\.[^@]+')
                                      .hasMatch(value.trim())) {
                                return 'Please enter a valid recovery email';
                              }
                              return null;
                            },
                          ),
                          v24,

                          // ── Sign Up button ──────────────────────────
                          SizedBox(
                            height: 56,
                            child: FilledButton(
                              onPressed: _isLoading ? null : _handleSignUp,
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const Text(
                                      'Sign Up',
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stitch-derived helper widgets
// ─────────────────────────────────────────────────────────────────────────────

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
