import 'package:flutter/material.dart';

/// A role-selection dialog that lets the user choose between
/// admin recovery (OTP flow) and teacher recovery (code from admin).
///
/// Returns `'admin'` or `'teacher'` via Navigator.pop, or `null` if cancelled.
class ForgotPasswordDialog extends StatelessWidget {
  const ForgotPasswordDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const ForgotPasswordDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Reset Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Are you an admin or a teacher?',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Admin option
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop('admin'),
              icon: const Icon(Icons.admin_panel_settings_rounded),
              label: const Text('I\'m an Admin'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Teacher option
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop('teacher'),
              icon: const Icon(Icons.person_rounded),
              label: const Text('I\'m a Teacher'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
