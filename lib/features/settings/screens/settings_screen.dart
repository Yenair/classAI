import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:classai/core/widgets/app_toast.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/sync_status_provider.dart';
import 'package:classai/features/settings/providers/theme_provider.dart';

void _goToLessonsDeferred(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    context.push('/lessons');
  });
}

/// Settings screen — redesigned to match Google Stitch bento grid layout.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = '${info.version}+${info.buildNumber}';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _appVersion = '—';
        });
      }
    }
  }

  Future<void> _showAboutClassAIDialog() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text('About ClassAI'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ClassAI'),
            const SizedBox(height: 12),
            Text('Version: ${info.version}'),
            Text('Build number: ${info.buildNumber}'),
            const SizedBox(height: 12),
            const Text(
              'Offline-first AI teaching assistant for Nigerian schools.',
            ),
            const SizedBox(height: 12),
            Text('© ${DateTime.now().year} ClassAI'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ref.read(authProvider.notifier).manualLogout();
                if (context.mounted) {
                  context.go('/login');
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Sign out failed: $e')),
                  );
                }
              }
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authData = ref.watch(authProvider);
    final syncData = ref.watch(syncStatusProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // === Desktop Nav Drawer ===
            if (isWide && !Platform.isAndroid) _buildNavDrawer(cs, textTheme, authData),

            // === Main Content ===
            Expanded(
              child: Column(
                children: [
                  // === TopAppBar (mobile + desktop) ===
                  _buildTopAppBar(cs, textTheme, authData, isWide),

                  // === Canvas ===
                  Expanded(
                    child: SingleChildScrollView(

                      physics: (Platform.isAndroid || Platform.isIOS)
                          ? const BouncingScrollPhysics()
                          : null,
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 896),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Bento Grid
                            _buildBentoGrid(
                              context,
                              cs,
                              textTheme,
                              authData,
                              syncData,
                              isDark,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // === BottomNav (mobile only; also on Android — no side nav) ===
                  if (!isWide || Platform.isAndroid) _buildBottomNav(cs, textTheme, authData),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Nav Drawer (Desktop)
  // ---------------------------------------------------------------
  Widget _buildNavDrawer(
      ColorScheme cs, TextTheme textTheme, AuthStateData authData) {
    return Container(
      width: 288,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          // Branding
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ClassAI',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Nigerian Academic Partner',
                  style: textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Educator avatar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _getInitials(
                          authData.currentTeacher?.teacherName ?? 'T'),
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  authData.currentTeacher?.teacherName ?? 'Educator Profile',
                  style: textTheme.labelLarge?.copyWith(
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Nav items
          Expanded(
            child: ListView(

              physics: (Platform.isAndroid || Platform.isIOS)
                  ? const BouncingScrollPhysics()
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                // Teacher-only nav items — hidden for admins
                if (authData.currentTeacher?.role != 'admin') ...[
                  _SettingsNavItem(
                      icon: Icons.home_rounded,
                      label: 'Home',
                      isActive: false,
                      cs: cs,
                      textTheme: textTheme,
                      onTap: () => context.go('/')),
                  const SizedBox(height: 4),
                  _SettingsNavItem(
                      icon: Icons.menu_book_rounded,
                      label: 'Lessons',
                      isActive: false,
                      cs: cs,
                      textTheme: textTheme,
                      onTap: () => _goToLessonsDeferred(context)),
                  const SizedBox(height: 4),
                  _SettingsNavItem(
                      icon: Icons.quiz_rounded,
                      label: 'Exams',
                      isActive: false,
                      cs: cs,
                      textTheme: textTheme,
                      onTap: () => context.push('/exams')),
                  const SizedBox(height: 4),
                ],
                // _SettingsNavItem(
                //     icon: Icons.inventory_2_rounded,
                //     label: 'Vault', // Vault feature disabled
                //     isActive: false,
                //     cs: cs,
                //     textTheme: textTheme,
                //     onTap: () => context.push('/vault')),
                // const SizedBox(height: 4),
                _SettingsNavItem(
                    icon: Icons.admin_panel_settings_rounded,
                    label: 'Admin',
                    isActive: false,
                    cs: cs,
                    textTheme: textTheme,
                    onTap: () => context.push('/admin')),
                const SizedBox(height: 4),
                _SettingsNavItem(
                    icon: Icons.settings_rounded,
                    label: 'Settings',
                    isActive: true,
                    cs: cs,
                    textTheme: textTheme,
                    onTap: null),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Top App Bar
  // ---------------------------------------------------------------
  Widget _buildTopAppBar(ColorScheme cs, TextTheme textTheme,
      AuthStateData authData, bool isWide) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // Mobile: avatar
          if (!isWide)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _getInitials(
                      authData.currentTeacher?.teacherName ?? 'E'),
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          if (!isWide) const SizedBox(width: 12),

          // Title
          Expanded(
            child: Text(
              'Settings',
              textAlign: isWide ? TextAlign.left : TextAlign.center,
              style: (isWide
                      ? textTheme.headlineSmall
                      : textTheme.titleLarge)
                  ?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
            ),
          ),

          // Spacer for mobile centering
          if (!isWide)
            const SizedBox(
                width: 52), // balance avatar on left
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Bento Grid
  // ---------------------------------------------------------------
  Widget _buildBentoGrid(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    AuthStateData authData,
    SyncStatusData syncData,
    bool isDark,
  ) {
    return Column(
      children: [
        _buildAppearanceCard(cs, textTheme, isDark),
        const SizedBox(height: 16),

        _buildAccountCard(context, cs, textTheme, authData),
        const SizedBox(height: 16),

        if (authData.currentTeacher?.role == 'admin') ...[
          _buildUpgradePlanCard(context, cs, textTheme, authData),
          const SizedBox(height: 16),
        ],

        _buildSyncCard(context, cs, textTheme, syncData),
        const SizedBox(height: 16),

        _buildAboutCard(context, cs, textTheme),
      ],
    );
  }

  // ---------------------------------------------------------------
  // Appearance Card
  // ---------------------------------------------------------------
  Widget _buildAppearanceCard(
      ColorScheme cs, TextTheme textTheme, bool isDark) {
    return _StitchCard(
      cs: cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.palette_rounded,
                size: 28,
                color: cs.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'Appearance',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Adjust the visual theme to suit your environment.',
            style: textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isDark ? 'Dark Theme' : 'Light Theme',
                      style: textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      'Current setting',
                      style: textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                // Toggle
                GestureDetector(
                  onTap: () {
                    ref.read(themeProvider.notifier).setTheme(
                          isDark ? ThemeMode.light : ThemeMode.dark,
                        );
                  },
                  child: Container(
                    width: 48,
                    height: 24,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 200),
                      alignment: isDark
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 20,
                        height: 20,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: cs.onPrimary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Account Card
  // ---------------------------------------------------------------
  Widget _buildAccountCard(BuildContext context, ColorScheme cs,
      TextTheme textTheme, AuthStateData authData) {
    return _StitchCard(
      cs: cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.person_rounded,
                size: 28,
                color: cs.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'Account',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Teacher info
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_rounded,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authData.currentTeacher?.teacherName ?? 'Teacher',
                      style: textTheme.titleMedium,
                    ),
                    Text(
                      authData.currentTeacher?.email ?? '',
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Recovery email (admin-only, read-only display)
          if (authData.currentSchool?.adminRecoveryEmail != null &&
              authData.currentSchool!.adminRecoveryEmail!.isNotEmpty)
            Row(
              children: [
                Icon(
                  Icons.mail_outline_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recovery Email',
                        style: textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        authData.currentSchool!.adminRecoveryEmail!,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.lock_rounded,
                  size: 14,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ],
            ),
          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),

        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Upgrade Plan Card
  // ---------------------------------------------------------------
  Widget _buildUpgradePlanCard(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    AuthStateData authData,
  ) {
    return _StitchCard(
      cs: cs,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
                        onTap: () => context.push('/payment'),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.workspace_premium_rounded,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upgrade Plan',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Compare tiers and upgrade to unlock more features.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Teacher seat usage label
            Row(
              children: [
                Icon(
                  Icons.people_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Teachers',
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '${authData.currentSchool?.totalSeats ?? 0} seats',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.push('/payment'),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Upgrade Plan'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Sync Card
  // ---------------------------------------------------------------
  Widget _buildSyncCard(BuildContext context, ColorScheme cs,
      TextTheme textTheme, SyncStatusData syncData) {
    return _StitchCard(
      cs: cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sync_rounded,
                size: 28,
                color: cs.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'Sync',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sync status rows
          _SyncStatusRow(
            label: 'Status',
            value: _syncStatusLabel(syncData.status),
            icon: _syncStatusIcon(syncData.status),
            iconColor: _syncStatusColor(syncData.status),
            cs: cs,
            textTheme: textTheme,
          ),
          const SizedBox(height: 6),
          _SyncStatusRow(
            label: 'Online',
            value: syncData.isOnline ? 'Yes' : 'No',
            icon: syncData.isOnline
                ? Icons.wifi_rounded
                : Icons.wifi_off_rounded,
            iconColor:
                syncData.isOnline ? cs.primary : cs.onSurfaceVariant,
            cs: cs,
            textTheme: textTheme,
          ),
          const SizedBox(height: 6),
          _SyncStatusRow(
            label: 'Pending pushes',
            value: '${syncData.pendingPushCount}',
            icon: Icons.upload_file_rounded,
            iconColor: cs.onSurfaceVariant,
            cs: cs,
            textTheme: textTheme,
          ),
          if (syncData.lastSyncTime != null) ...[
            const SizedBox(height: 6),
            _SyncStatusRow(
              label: 'Last sync',
              value: _formatDateTime(syncData.lastSyncTime!),
              icon: Icons.access_time_rounded,
              iconColor: cs.onSurfaceVariant,
              cs: cs,
              textTheme: textTheme,
            ),
          ],
          const SizedBox(height: 16),

          // Sync Actions
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recovery Actions',
                style: textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'If you are missing content or sync seems stuck, use the button below to perform a fresh data pull.',
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () async {
                    final proceed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: cs.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        title: const Text('Force Full Resync?'),
                        content: const Text(
                          'This will re-download all data from the server. This may take longer than normal. Continue?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Continue'),
                          ),
                        ],
                      ),
                    );

                    if (proceed == true) {
                      try {
                        final hasPushFailures = await ref
                            .read(syncStatusProvider.notifier)
                            .forceFullResync();
                        
                        if (hasPushFailures && context.mounted) {
                          await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: cs.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              title: const Text('Unsaved Changes Not Synced'),
                              content: const Text(
                                'Some local changes could not be sent to the server. These changes may be lost when the full resync overwrites local data. Check the sync queue for details.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                        }
                        
                        if (context.mounted) {
                          showInfoToast(
                              context: context,
                              message: 'Full resync completed');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showErrorToast(
                              context: context,
                              message: 'Failed to initiate resync: $e');
                        }
                      }
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.secondaryContainer,
                    foregroundColor: cs.onSecondaryContainer,
                  ),
                  icon: const Icon(Icons.sync_problem_rounded),
                  label: const Text('Force Full Resync'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // About Card
  // ---------------------------------------------------------------
  Widget _buildAboutCard(
      BuildContext context, ColorScheme cs, TextTheme textTheme) {
    return _StitchCard(
      cs: cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 28,
                color: cs.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'About',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Version
          Row(
            children: [
              Icon(
                Icons.info_outlined,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'App Version',
                  style: textTheme.bodyMedium,
                ),
              ),
              Text(
                _appVersion.isEmpty ? '—' : _appVersion,
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 8),

          // Privacy Policy
          InkWell(
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: cs.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  title: const Text('Privacy Policy'),
                  content: const SingleChildScrollView(
                    child: Text(
                      'ClassAI Privacy Policy\n\n'
                      '1. Data We Collect\n'
                      'We collect teacher name, email address, school details, '
                      'and lesson/exam content you create. We do not collect '
                      'sensitive personal data beyond what is necessary for '
                      'the service.\n\n'
                      '2. How We Use Data\n'
                      'Your data is used to provide and improve the ClassAI '
                      'platform, sync content across devices, and generate '
                      'PDF exports and AI-assisted content. We do not sell '
                      'your data to third parties.\n\n'
                      '3. Data Storage & Security\n'
                      'Content is encrypted at rest using AES-256. '
                      'Authentication tokens and session keys are stored '
                      'locally on your device. Server-side data is stored '
                      'in secure Supabase infrastructure with row-level '
                      'security policies.\n\n'
                      '4. Data Sharing\n'
                      'We do not share your personal data with third parties '
                      'except as required by law or with your explicit consent. '
                      'Vault content submitted for publication is reviewed by '
                      'administrators before being made visible.\n\n'
                      '5. Your Rights\n'
                      'You may request deletion of your account and associated '
                      'data at any time by contacting support. You can export '
                      'your data via the Settings screen.\n\n'
                      '6. Changes to This Policy\n'
                      'We may update this policy from time to time. Significant '
                      'changes will be notified through the app.\n\n'
                      'Last updated: June 2026',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
            child: Row(
              children: [
                Icon(
                  Icons.privacy_tip_outlined,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Privacy Policy',
                    style: textTheme.bodyMedium,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // System Actions row
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                // About button
                Expanded(
                  child: InkWell(
                    onTap: _showAboutClassAIDialog,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.info_rounded,
                            size: 20,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'About ClassAI',
                            style: textTheme.labelLarge?.copyWith(
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 32,
                  color:
                      cs.outlineVariant.withValues(alpha: 0.3),
                ),
                // Logout button
                Expanded(
                  child: InkWell(
                    onTap: () => _showLogoutConfirmation(),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.logout_rounded,
                            size: 20,
                            color: cs.error,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Secure Logout',
                            style: textTheme.labelLarge?.copyWith(
                              color: cs.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Bottom Navigation (Mobile)
  // ---------------------------------------------------------------
  Widget _buildBottomNav(
      ColorScheme cs, TextTheme textTheme, AuthStateData authData) {
    final isAdmin = authData.currentTeacher?.role == 'admin';
    final items = [
      if (!isAdmin)
        _NavItem(icon: Icons.home_rounded, label: 'Home', route: '/'),
      if (!isAdmin)
        _NavItem(icon: Icons.menu_book_rounded, label: 'Lessons', route: '/lessons'),
      if (!isAdmin)
        _NavItem(icon: Icons.quiz_rounded, label: 'Exams', route: '/exams'),
      _NavItem(icon: Icons.more_horiz_rounded, label: 'More', route: null),
    ];

    return Container(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items.map((item) {
          final isActive = item.label == 'More';
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: isActive ? cs.secondaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              icon: Icon(
                item.icon,
                color: isActive ? cs.onSecondaryContainer : cs.onSurfaceVariant,
              ),
              onPressed: item.route != null ? () => context.go(item.route!) : null,
            ),
          );
        }).toList(),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------
  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String _syncStatusLabel(SyncStatus status) {
    switch (status) {
      case SyncStatus.offline:
        return 'Offline';
      case SyncStatus.syncing:
        return 'Syncing\u2026';
      case SyncStatus.synced:
        return 'Synced';
      case SyncStatus.error:
        return 'Error';
    }
  }

  IconData _syncStatusIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.offline:
        return Icons.cloud_off_rounded;
      case SyncStatus.syncing:
        return Icons.sync_rounded;
      case SyncStatus.synced:
        return Icons.cloud_done_rounded;
      case SyncStatus.error:
        return Icons.error_outline_rounded;
    }
  }

  Color _syncStatusColor(SyncStatus status) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case SyncStatus.offline:
        return cs.onSurfaceVariant;
      case SyncStatus.syncing:
        return cs.primary;
      case SyncStatus.synced:
        return cs.primary;
      case SyncStatus.error:
        return cs.error;
    }
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// Nav item data class for bottom navigation bar.
class _NavItem {
  final IconData icon;
  final String label;
  final String? route;
  const _NavItem({required this.icon, required this.label, this.route});
}

// ---------------------------------------------------------------------------
// Stitch Card Wrapper
// ---------------------------------------------------------------------------
class _StitchCard extends StatelessWidget {
  final ColorScheme cs;
  final Widget child;

  const _StitchCard({required this.cs, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Settings Nav Item
// ---------------------------------------------------------------------------
class _SettingsNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final ColorScheme cs;
  final TextTheme textTheme;
  final VoidCallback? onTap;

  const _SettingsNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.cs,
    required this.textTheme,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive
              ? cs.secondaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        transform: isActive
            ? Matrix4.translationValues(4.0, 0.0, 0.0)
            : Matrix4.identity(),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isActive
                  ? cs.onSecondaryContainer
                  : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: textTheme.labelLarge?.copyWith(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive
                    ? cs.onSecondaryContainer
                    : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sync Status Row
// ---------------------------------------------------------------------------
class _SyncStatusRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final ColorScheme cs;
  final TextTheme textTheme;

  const _SyncStatusRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.cs,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              '$label:',
              style: textTheme.bodyMedium?.copyWith(
                overflow: TextOverflow.clip,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                overflow: TextOverflow.clip,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

