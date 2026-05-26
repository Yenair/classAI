import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/settings/providers/theme_provider.dart';
import '../theme/app_theme.dart';

/// A profile menu that slides up from the bottom with a spring animation.
///
/// Uses [showModalBottomSheet] with a rounded top sheet containing
/// the teacher's name/email, theme selection, settings, and logout.
class ProfileSlideUpMenu extends StatelessWidget {
  final Widget child;
  final ThemeMode themeMode;
  final WidgetRef ref;
  final String? teacherName;
  final String? teacherEmail;
  final VoidCallback onSettings;
  final VoidCallback onLogout;

  const ProfileSlideUpMenu({
    super.key,
    required this.child,
    required this.themeMode,
    required this.ref,
    this.teacherName,
    this.teacherEmail,
    required this.onSettings,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showMenu(context),
      child: child,
    );
  }

  void _showMenu(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusXl),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppTheme.spacingBase,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Drag handle ──
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingGutter),

                // ── Teacher info header ──
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingMarginMobile,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        teacherName ?? 'Educator',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        teacherEmail ?? '',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),

                // ── Theme label ──
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingMarginMobile,
                  ),
                  child: Text(
                    'Theme',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Light'),
                  value: ThemeMode.light,
                  groupValue: themeMode,
                  onChanged: (value) {
                    ref.read(themeProvider.notifier).setTheme(value!);
                    Navigator.pop(context);
                  },
                  activeColor: cs.primary,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingMarginMobile,
                  ),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Dark'),
                  value: ThemeMode.dark,
                  groupValue: themeMode,
                  onChanged: (value) {
                    ref.read(themeProvider.notifier).setTheme(value!);
                    Navigator.pop(context);
                  },
                  activeColor: cs.primary,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingMarginMobile,
                  ),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('System'),
                  value: ThemeMode.system,
                  groupValue: themeMode,
                  onChanged: (value) {
                    ref.read(themeProvider.notifier).setTheme(value!);
                    Navigator.pop(context);
                  },
                  activeColor: cs.primary,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingMarginMobile,
                  ),
                ),
                const Divider(),

                // ── Settings ──
                ListTile(
                  leading: Icon(
                    Icons.settings_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                  title: const Text('Settings'),
                  onTap: () {
                    Navigator.pop(context);
                    onSettings();
                  },
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingMarginMobile,
                  ),
                ),

                // ── Logout ──
                ListTile(
                  leading: Icon(
                    Icons.logout_rounded,
                    color: cs.error,
                  ),
                  title: Text(
                    'Logout',
                    style: TextStyle(color: cs.error),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onLogout();
                  },
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingMarginMobile,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
