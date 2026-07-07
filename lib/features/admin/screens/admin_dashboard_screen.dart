// lib/features/admin/screens/admin_dashboard_screen.dart
import 'dart:async';

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;
import 'package:classai/features/admin/providers/admin_provider.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/core/services/auth_service.dart';
import 'package:classai/core/theme/app_theme.dart';
import 'package:classai/core/widgets/app_toast.dart';
import 'package:classai/core/widgets/sync_indicator.dart';
import 'package:classai/features/dashboard/providers/sync_status_provider.dart';
import 'package:classai/features/settings/providers/theme_provider.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Admin dashboard screen with teacher management, vault approval queue,
/// sync health overview, and pending teachers view — redesigned to match Google Stitch.
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  int _selectedTabIndex = 0;
  bool _sidebarOpen = true;
  Timer? _autoRefreshTimer;

  /// Shows a confirmation dialog when the system back button is pressed on the
  /// admin home route (`/admin`). If the user confirms, the app is closed.
  void _onBackPressed(bool didPop) {
    if (didPop) return;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text('Quit App'),
        content: const Text('Are you sure you want to quit the app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop(true);
              SystemNavigator.pop();
            },
            child: const Text('Quit'),
          ),
        ],
      ),
    );
  }


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // First load whatever is already in the local DB
      ref.read(adminDashboardProvider.notifier).refresh();

      // Then trigger a direct pull (bypasses biometric/session gate)
      // Pass the JWT so the edge function can authenticate, and
      // override the schoolId with the correct one from auth state
      // (the local DB may have a stale school record).
      ref.read(syncServiceProvider.future).then((syncService) {
        final jwt = ref.read(authServiceProvider).currentJwt;
        final adminSchoolId = ref.read(authProvider).currentSchool?.serverId;
        syncService.pullNow(jwt: jwt, overrideSchoolId: adminSchoolId).then((_) {
          // Refresh the admin UI after the pull completes
          if (mounted) {
            ref.read(adminDashboardProvider.notifier).refresh();
          }
        });
      });
    });

    // Auto-refresh admin data every 30 seconds to stay in sync
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (mounted) {
          ref.read(adminDashboardProvider.notifier).refresh();
        }
      },
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboardData = ref.watch(adminDashboardProvider);
    final authData = ref.watch(authProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isWide = MediaQuery.of(context).size.width >= 768;
    final themeMode = ref.watch(themeProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onBackPressed(didPop),
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // === Desktop Nav Drawer ===
              if (isWide) _buildNavDrawer(cs, textTheme),

              // === Main Content Area ===
              Expanded(
                child: Column(
                  children: [
                    // === TopAppBar (desktop only) ===
                    if (isWide)
                      _buildTopAppBar(cs, textTheme, authData, themeMode),

                    // === Main canvas ===
                    Expanded(
                      child: dashboardData.loading
                          ? const Center(child: CircularProgressIndicator())
                          : dashboardData.errorMessage != null
                              ? _buildErrorState(cs, textTheme, dashboardData)
                              : _buildCanvas(context, cs, textTheme,
                                  dashboardData, authData),
                    ),

                    // === BottomNav (mobile only) ===
                    if (!isWide) _buildBottomNav(cs, textTheme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Navigation Drawer (Desktop)
  // ---------------------------------------------------------------
  Widget _buildNavDrawer(ColorScheme cs, TextTheme textTheme) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: _sidebarOpen ? 288 : 72,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(height: _sidebarOpen ? 24 : 16),
          // Branding header — tapping toggles sidebar
          InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            onTap: () => setState(() => _sidebarOpen = !_sidebarOpen),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _sidebarOpen ? 24 : 12,
              ),
              child: _sidebarOpen
                  ? Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.school_rounded,
                            color: cs.onPrimaryContainer,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ClassAI',
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: cs.primary,
                                fontSize: 28,
                              ),
                            ),
                            Text(
                              'Nigerian Academic Partner',
                              style: textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Center(
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.menu_rounded,
                          color: cs.onPrimaryContainer,
                          size: 24,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Divider(
            height: 1,
            thickness: 1,
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          // Navigation items — admin-specific sidebar
          Expanded(
            child: ListView(

              physics: (Platform.isAndroid || Platform.isIOS)
                  ? const BouncingScrollPhysics()
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _NavItem(
                  icon: Icons.people_rounded,
                  label: 'Teacher Management',
                  isActive: _selectedTabIndex == 0,
                  onTap: () => setState(() => _selectedTabIndex = 0),
                ),
                const SizedBox(height: 4),
                _NavItem(
                  icon: Icons.person_add_rounded,
                  label: 'Pending Teachers',
                  isActive: _selectedTabIndex == 1,
                  onTap: () => setState(() => _selectedTabIndex = 1),
                ),
                const SizedBox(height: 4),
                // _NavItem( // Vault feature disabled
                //   icon: Icons.verified_rounded,
                //   label: 'Vault Approve Queue',
                //   isActive: _selectedTabIndex == 2,
                //   onTap: () => setState(() => _selectedTabIndex = 2),
                // ),
                // const SizedBox(height: 4),
                _NavItem(
                  icon: Icons.sync_rounded,
                  label: 'Sync Health',
                  isActive: _selectedTabIndex == 2,
                  onTap: () => setState(() => _selectedTabIndex = 2),
                ),
                const SizedBox(height: 4),
                _NavItem(
                  icon: Icons.calendar_month_rounded,
                  label: 'Scheme of Work',
                  isActive: false,
                  onTap: () => context.push('/scheme-of-work'),
                ),
                const SizedBox(height: 4),
                _NavItem(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  isActive: false,
                  onTap: () => context.push('/settings'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Top App Bar (Desktop)
  // ---------------------------------------------------------------
  Widget _buildTopAppBar(ColorScheme cs, TextTheme textTheme,
      AuthStateData authData, ThemeMode themeMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(
            color: cs.surfaceContainerHighest,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Title
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'Admin Dashboard',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                      overflow: TextOverflow.clip,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Right side actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sync status chip (live from syncStatusProvider) — clickable to trigger sync
              const _AdminSyncChip(),
              const SizedBox(width: 12),
              // Sync Indicator (opens sync details sheet)
              const SyncIndicator(),
              const SizedBox(width: 12),
              // Notifications
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.notifications_rounded,
                    color: cs.onPrimaryContainer,
                    size: 20,
                  ),
                  onPressed: () {
                    showInfoToast(
                      context: context,
                      message: 'Notifications coming soon.',
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Profile popup
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'redeem_code':
                      showDialog(
                        context: context,
                        builder: (_) => const _RedeemCodeDialog(),
                      );
                      break;
                    case 'settings':
                      context.push('/settings');
                      break;
                    case 'logout':
                      _showLogoutConfirmation(context, ref);
                      break;
                    case 'theme_light':
                      ref
                          .read(themeProvider.notifier)
                          .setTheme(ThemeMode.light);
                      break;
                    case 'theme_dark':
                      ref.read(themeProvider.notifier).setTheme(ThemeMode.dark);
                      break;
                    case 'theme_system':
                      ref
                          .read(themeProvider.notifier)
                          .setTheme(ThemeMode.system);
                      break;
                  }
                },
                offset: const Offset(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                ),
                itemBuilder: (context) {
                  final teacher = authData.currentTeacher;
                  return [
                    PopupMenuItem<String>(
                      enabled: false,
                      child: SizedBox(
                        width: 200,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              teacher?.teacherName ?? 'Admin',
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              teacher?.email ?? '',
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      enabled: false,
                      child: Text(
                        'Theme',
                        style: textTheme.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    CheckedPopupMenuItem<String>(
                      checked: themeMode == ThemeMode.light,
                      value: 'theme_light',
                      child: const Text('Light'),
                    ),
                    CheckedPopupMenuItem<String>(
                      checked: themeMode == ThemeMode.dark,
                      value: 'theme_dark',
                      child: const Text('Dark'),
                    ),
                    CheckedPopupMenuItem<String>(
                      checked: themeMode == ThemeMode.system,
                      value: 'theme_system',
                      child: const Text('System'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem<String>(
                      value: 'redeem_code',
                      child: ListTile(
                        leading: Icon(Icons.vpn_key_rounded),
                        title: Text('Redeem Code'),
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem<String>(
                      value: 'settings',
                      child: ListTile(
                        leading: Icon(Icons.settings_rounded),
                        title: Text('Settings'),
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'logout',
                      child: ListTile(
                        leading: Icon(Icons.logout_rounded),
                        title: Text('Logout'),
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ];
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.surface, width: 2),
                    color: cs.primaryContainer,
                  ),
                  child: Center(
                    child: Text(
                      _initialsFromName(authData.currentTeacher?.teacherName),
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Error State
  // ---------------------------------------------------------------
  Widget _buildErrorState(
      ColorScheme cs, TextTheme textTheme, AdminDashboardData dashboardData) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: cs.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Error: ${dashboardData.errorMessage}',
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge?.copyWith(color: cs.error),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  ref.read(adminDashboardProvider.notifier).refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Main Canvas
  // ---------------------------------------------------------------
  Widget _buildCanvas(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    AdminDashboardData dashboardData,
    AuthStateData authData,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // === Context Tabs ===
              _buildContextTabs(cs, textTheme),

              const SizedBox(height: 6),

              // === Tab Content ===
              Expanded(
                child: _buildTabContent(
                    context, cs, textTheme, dashboardData, authData, isWide),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------
  // Context Tabs
  // ---------------------------------------------------------------
  Widget _buildContextTabs(ColorScheme cs, TextTheme textTheme) {
    final tabs = [
      'Teacher Management',
      'Pending Teachers',
      // 'Vault Approval Queue', // Vault feature disabled
      'Sync Health',
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(

        physics: (Platform.isAndroid || Platform.isIOS)
            ? const BouncingScrollPhysics()
            : null,
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 0),
        itemBuilder: (context, index) {
          final isActive = _selectedTabIndex == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedTabIndex = index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: isActive
                    ? Border(
                        bottom: BorderSide(
                          color: cs.primary,
                          width: 2,
                        ),
                      )
                    : null,
              ),
              child: Text(
                tabs[index],
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------
  // Tab Content Dispatcher
  // ---------------------------------------------------------------
  Widget _buildTabContent(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    AdminDashboardData dashboardData,
    AuthStateData authData,
    bool isWide,
  ) {
    switch (_selectedTabIndex) {
      case 0:
        return _TeacherManagementTab(
          teachers: dashboardData.teachers,
          authData: authData,
          isWide: isWide,
        );
      case 1:
        return _PendingTeachersTab(
          pendingTeachers: dashboardData.pendingTeachers,
          authData: authData,
        );
      // case 2:
      //   return _VaultApprovalTab(authData: authData); // Vault feature disabled
      case 2:
        return _SyncHealthTab(
          teachers: dashboardData.teachers,
          dashboardData: dashboardData,
          isWide: isWide,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // ---------------------------------------------------------------
  // Bottom Navigation (Mobile)
  // ---------------------------------------------------------------
  Widget _buildBottomNav(ColorScheme cs, TextTheme textTheme) {
    final items = [
      (icon: Icons.people_rounded, label: 'Management'),
      (icon: Icons.person_add_rounded, label: 'Pending'),
      // (icon: Icons.verified_rounded, label: 'Vault Queue'), // Vault feature disabled
      (icon: Icons.sync_rounded, label: 'Sync'),
      (icon: Icons.calendar_month_rounded, label: 'Scheme of Work'),
      (icon: Icons.settings_rounded, label: 'Settings'),
    ];

    return Container(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final isActive = _selectedTabIndex == i;
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: isActive ? cs.secondaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              icon: Icon(
                item.icon,
                color: isActive ? cs.onSecondaryContainer : cs.onSurfaceVariant,
              ),
              onPressed: () {
                if (i == 4) {
                  context.push('/scheme-of-work');
                } else if (i == 5) {
                  context.push('/settings');
                } else {
                  setState(() => _selectedTabIndex = i);
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context, WidgetRef ref) {
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
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(authProvider.notifier).manualLogout();
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  String _initialsFromName(String? name) {
    if (name == null || name.trim().isEmpty) return 'AD';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final single = parts[0].trim();
    return single.length >= 2
        ? single.substring(0, 2).toUpperCase()
        : '${single[0]}D'.toUpperCase();
  }
}

// ---------------------------------------------------------------------------
// Navigation Item Helper
// ---------------------------------------------------------------------------
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? cs.secondaryContainer : Colors.transparent,
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
              color: isActive ? cs.onSecondaryContainer : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
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
  // Sync Status Chip (online/offline indicator with one-tap sync)
  // ---------------------------------------------------------------------------
  class _AdminSyncChip extends ConsumerWidget {
    const _AdminSyncChip();
  
    @override
    Widget build(BuildContext context, WidgetRef ref) {
      final syncData = ref.watch(syncStatusProvider);
      final cs = Theme.of(context).colorScheme;
  
      final label = statusLabel(syncData.status);
      final Color dotColor = switch (syncData.status) {
        SyncStatus.synced => cs.primary,
        SyncStatus.syncing => cs.primary,
        SyncStatus.error => cs.error,
        SyncStatus.offline => cs.onSurfaceVariant,
      };
  
      final isSyncing = syncData.status == SyncStatus.syncing;
  
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isSyncing
              ? null
              : () => ref.read(syncStatusProvider.notifier).syncNow(),
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: dotColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              border: Border.all(
                color: dotColor.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: dotColor,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }
  
  // ---------------------------------------------------------------------------
  // Add Teacher Dialog
  // ---------------------------------------------------------------------------

class _AddTeacherDialog extends ConsumerStatefulWidget {
  const _AddTeacherDialog();

  @override
  ConsumerState<_AddTeacherDialog> createState() => _AddTeacherDialogState();
}

class _AddTeacherDialogState extends ConsumerState<_AddTeacherDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  String _selectedRole = 'teacher';
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authProvider.notifier).addTeacher(
            email: _emailController.text.trim(),
            teacherName: _nameController.text.trim(),
            role: _selectedRole,
          );

      if (!mounted) return;
      Navigator.of(context).pop();
      showInfoToast(
        context: context,
        message: 'Teacher added. A temporary password has been emailed.',
      );
      // Refresh the admin dashboard to show the new teacher
      ref.read(adminDashboardProvider.notifier).refresh();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Failed to add teacher. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      title: Text(
        'Add Teacher',
        style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(

          physics: (Platform.isAndroid || Platform.isIOS)
              ? const BouncingScrollPhysics()
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Error message
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: cs.error.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: cs.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: cs.onErrorContainer,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Email field
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
                    return 'Please enter an email';
                  }
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Teacher Name field
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Teacher Name',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter the teacher name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Role dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  prefixIcon: Icon(Icons.badge_rounded),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'teacher',
                    child: Text('Teacher'),
                  ),
                  DropdownMenuItem(
                    value: 'admin',
                    child: Text('Admin'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedRole = value);
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _handleSubmit,
          child: _isSubmitting
              ? SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Redeem Activation Code Dialog
// ---------------------------------------------------------------------------

class _RedeemCodeDialog extends ConsumerStatefulWidget {
const _RedeemCodeDialog();

@override
ConsumerState<_RedeemCodeDialog> createState() => _RedeemCodeDialogState();
}

class _RedeemCodeDialogState extends ConsumerState<_RedeemCodeDialog> {
final _formKey = GlobalKey<FormState>();
final _codeController = TextEditingController();
bool _isSubmitting = false;
String? _errorMessage;

@override
void dispose() {
  _codeController.dispose();
  super.dispose();
}

Future<void> _handleSubmit() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() {
    _isSubmitting = true;
    _errorMessage = null;
  });

  try {
    final authData = ref.read(authProvider);
    final school = authData.currentSchool ??
        await ref.read(databaseProvider).schoolsDao.get();
    final serverId = school?.serverId;
    final teacher = authData.currentTeacher;
    final email = teacher == null ? null : teacher.email.trim();
    final cachedSchool = authData.currentSchool;
    final schoolName = cachedSchool == null
        ? school?.schoolName.trim()
        : cachedSchool.schoolName.trim();

    if (email == null ||
        email.isEmpty ||
        schoolName == null ||
        schoolName.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'School details are missing. Please sync and try again.';
      });
      return;
    }

    if (serverId == null) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'School not found. Sync your data first.';
      });
      return;
    }

    final code = _codeController.text.trim().toUpperCase();

    final response = await Supabase.instance.client.functions
        .invoke('redeem-activation', body: {
          'code': code,
          'email': email,
          'school_name': schoolName,
        });

    if (response.data != null && response.data is Map) {
      final data = response.data as Map<String, dynamic>;
      final tier = data['subscription_tier'] as String? ??
          data['tier'] as String? ??
          'standard';
      final expiryStr =
          data['expiry_date'] as String? ?? data['expiry'] as String?;
      final expiry = expiryStr != null ? DateTime.tryParse(expiryStr) : null;
      final activationCode =
          data['activation_code'] as String? ?? data['code'] as String? ?? code;

      await ref.read(databaseProvider).schoolsDao.updateSubscriptionFields(
            serverId: serverId,
            subscriptionTier: tier,
            expiryDate: expiry,
            activationCode: activationCode,
          );
    }

    await ref.read(authProvider.notifier).refreshSchoolFromDb();

    if (!mounted) return;
    Navigator.of(context).pop();
    final responseData = response.data;
    final tier = responseData is Map<String, dynamic>
        ? responseData['subscription_tier'] as String? ??
            responseData['tier'] as String? ??
            'standard'
        : 'standard';
    final expiryStr = responseData is Map<String, dynamic>
        ? responseData['expiry_date'] as String? ??
            responseData['expiry'] as String?
        : null;
    final expiry = expiryStr != null ? DateTime.tryParse(expiryStr) : null;
    showInfoToast(
      context: context,
      message:
          'Activation code applied successfully. Tier: $tier, expiry: ${expiry?.toLocal().toString() ?? 'unknown'}.',
    );
  } catch (e) {
    if (!mounted) return;
    String message = 'Failed to redeem code. Please try again.';
    final errorStr = e.toString();
    if (errorStr.contains('already used activation code')) {
      message = 'Invalid or already used activation code.';
    } else if (errorStr.contains('400') || errorStr.contains('Invalid code')) {
      message = 'Invalid activation code format.';
    } else if (errorStr.contains('404') || errorStr.contains('not found')) {
      message = 'Activation code not found.';
    }
    setState(() {
      _isSubmitting = false;
      _errorMessage = message;
    });
  }
}

@override
Widget build(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;

  return AlertDialog(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    title: Text(
      'Redeem Activation Code',
      style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    ),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        physics: (Platform.isAndroid || Platform.isIOS)
            ? const BouncingScrollPhysics()
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Error message
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: cs.error.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: cs.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: cs.onErrorContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Activation code field
            TextFormField(
              controller: _codeController,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Activation Code',
                hintText: 'CLA-XXXX-XXXX-XXXX',
                prefixIcon: Icon(Icons.vpn_key_rounded),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter an activation code';
                }
                if (!RegExp(
                  r'^CLA-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$',
                  caseSensitive: false,
                ).hasMatch(value.trim())) {
                  return 'Format: CLA-XXXX-XXXX-XXXX';
                }
                return null;
              },
              onFieldSubmitted: _isSubmitting ? null : (_) => _handleSubmit(),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _isSubmitting ? null : _handleSubmit,
        child: _isSubmitting
            ? SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              )
            : const Text('Redeem'),
      ),
    ],
  );
}
}

// ---------------------------------------------------------------------------
// Teacher Management Tab
// ---------------------------------------------------------------------------

class _TeacherManagementTab extends ConsumerStatefulWidget {
  final List<TeacherAdminData> teachers;
  final AuthStateData authData;
  final bool isWide;

  const _TeacherManagementTab({
    required this.teachers,
    required this.authData,
    required this.isWide,
  });

  @override
  ConsumerState<_TeacherManagementTab> createState() =>
      _TeacherManagementTabState();
}

class _TeacherManagementTabState extends ConsumerState<_TeacherManagementTab> {
  String _filterStatus = 'all';
  bool _showOnlyNoScheme = false;

  List<TeacherAdminData> get _filteredTeachers {
    return widget.teachers.where((t) {
      if (_filterStatus != 'all' && t.statusColor != _filterStatus) {
        return false;
      }
      if (_showOnlyNoScheme && t.schemeStatus != 'none') {
        return false;
      }
      return true;
    }).toList();
  }

  String get _filterLabel {
    switch (_filterStatus) {
      case 'green':
        return 'Synced';
      case 'yellow':
        return 'Syncing';
      case 'red':
        return 'Error';
      case 'gray':
        return 'Offline';
      default:
        return 'All';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Empty state
    if (widget.teachers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 64,
              color: cs.onSurfaceVariant.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              'No teachers found.',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => _showAddTeacherDialog(context, ref),
              child: const Text('Add Teacher'),
            ),
          ],
        ),
      );
    }

    // -- Teacher Roster Card --
    return SingleChildScrollView(

      physics: (Platform.isAndroid || Platform.isIOS)
          ? const BouncingScrollPhysics()
          : null,
      padding: const EdgeInsets.only(bottom: 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Roster card
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Teacher Roster',
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Manage sync access and profile details.',
                            style: textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Filter + Add Teacher buttons
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Filter button
                        InkWell(
                          onTap: () => _showFilterMenu(context, cs, textTheme),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _filterStatus != 'all'
                                    ? cs.primary
                                    : cs.outlineVariant.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.filter_list_rounded,
                                    size: 18,
                                    color: _filterStatus != 'all'
                                        ? cs.primary
                                        : cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _filterLabel,
                                    style: textTheme.labelMedium?.copyWith(
                                      color: _filterStatus != 'all'
                                          ? cs.primary
                                          : cs.onSurfaceVariant,
                                      fontWeight: _filterStatus != 'all'
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Add Teacher button
                        FilledButton.icon(
                          onPressed: () => _showAddTeacherDialog(context, ref),
                          icon: const Icon(Icons.person_add_rounded, size: 20),
                          label: const Text('Add Teacher'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('No Scheme'),
                      selected: _showOnlyNoScheme,
                      onSelected: (value) {
                        setState(() => _showOnlyNoScheme = value);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Filtered teacher cards list
                ..._filteredTeachers.map((teacher) {
                  return _TeacherCardWidget(
                    teacher: teacher,
                    cs: cs,
                    textTheme: textTheme,
                    onDetailsTap: () {
                      context.push('/admin/teachers/${teacher.localId}');
                    },
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterMenu(
      BuildContext context, ColorScheme cs, TextTheme textTheme) {
    final RenderBox? button = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;

    final buttonRect = button != null
        ? button.localToGlobal(Offset.zero) & button.size
        : Offset.zero & const Size(200, 48);
    final overlayRect =
        overlay != null ? Offset.zero & overlay.size : Offset.zero & Size.zero;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(buttonRect, overlayRect),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      items: [
        PopupMenuItem<String>(
          value: 'all',
          child: _buildFilterItem('All', 'all', cs, textTheme),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'green',
          child: _buildFilterItem('Synced', 'green', cs, textTheme),
        ),
        PopupMenuItem<String>(
          value: 'yellow',
          child: _buildFilterItem('Syncing', 'yellow', cs, textTheme),
        ),
        PopupMenuItem<String>(
          value: 'red',
          child: _buildFilterItem('Error', 'red', cs, textTheme),
        ),
        PopupMenuItem<String>(
          value: 'gray',
          child: _buildFilterItem('Offline', 'gray', cs, textTheme),
        ),
      ],
    ).then((value) {
      if (value != null && mounted) {
        setState(() => _filterStatus = value);
      }
    });
  }

  Widget _buildFilterItem(
      String label, String value, ColorScheme cs, TextTheme textTheme) {
    final isSelected = _filterStatus == value;
    return Row(
      children: [
        if (value != 'all')
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: _statusDotColor(value),
              shape: BoxShape.circle,
            ),
          ),
        Text(
          label,
          style: textTheme.labelLarge?.copyWith(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? cs.primary : cs.onSurface,
          ),
        ),
        const Spacer(),
        if (isSelected) Icon(Icons.check, size: 18, color: cs.primary),
      ],
    );
  }

  Color _statusDotColor(String status) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case 'green':
        return Colors.green;
      case 'yellow':
        return cs.tertiary;
      case 'red':
        return cs.error;
      default:
        return cs.onSurfaceVariant;
    }
  }

  void _showAddTeacherDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => const _AddTeacherDialog(),
    );
  }
}

// ---------------------------------------------------------------------------
// Teacher Card Widget
// ---------------------------------------------------------------------------

class _TeacherCardWidget extends StatelessWidget {
  final TeacherAdminData teacher;
  final ColorScheme cs;
  final TextTheme textTheme;
  final VoidCallback onDetailsTap;

  const _TeacherCardWidget({
    required this.teacher,
    required this.cs,
    required this.textTheme,
    required this.onDetailsTap,
  });

  @override
  Widget build(BuildContext context) {
    final initials = _getInitials(teacher.teacherName);
    final statusColor = _statusColor(teacher.statusColor);
    final isError = teacher.statusColor == 'red';
    final schemeColor = _schemeStatusColor(teacher.schemeStatus);
    final schemeLabel = _schemeStatusLabel(teacher.schemeStatus);
    final hasSchemeProgress = teacher.totalWeeks > 0;
    final progressValue = hasSchemeProgress
        ? (teacher.completedWeeks / teacher.totalWeeks).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _avatarBgColor(teacher.statusColor),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _avatarTextColor(teacher.statusColor),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.surface, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  teacher.teacherName,
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${teacher.email} ? ${teacher.role}'
                  '${teacher.generatedCount > 0 ? ' ? ${teacher.generatedCount} generated' : ''}'
                  '${teacher.completedCount > 0 ? ' ? ${teacher.completedCount} completed' : ''}'
                  '${teacher.deviceCount > 0 ? ' ? ${teacher.deviceCount} device(s)' : ''}',
                  style: textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        schemeLabel,
                        style: textTheme.labelSmall?.copyWith(
                          color: schemeColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: schemeColor.withValues(alpha: 0.12),
                      side: BorderSide(
                        color: schemeColor.withValues(alpha: 0.25),
                      ),
                    ),
                    if (hasSchemeProgress)
                      SizedBox(
                        width: 220,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(
                              value: progressValue,
                              minHeight: 6,
                              backgroundColor:
                                  cs.outlineVariant.withValues(alpha: 0.25),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                cs.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Week ${teacher.completedWeeks} of ${teacher.totalWeeks} completed',
                              style: textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Action Required',
                    style: textTheme.labelMedium?.copyWith(
                      color: cs.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              OutlinedButton(
                onPressed: onDetailsTap,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(color: cs.outline),
                  ),
                ),
                child: Text(
                  'Details',
                  style: textTheme.labelMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'green':
        return cs.primary;
      case 'yellow':
        return cs.tertiary;
      case 'red':
        return cs.error;
      default:
        return cs.onSurfaceVariant;
    }
  }

  Color _avatarBgColor(String status) {
    switch (status) {
      case 'green':
        return cs.primaryContainer.withValues(alpha: 0.3);
      case 'yellow':
        return cs.tertiaryContainer.withValues(alpha: 0.3);
      default:
        return cs.surfaceContainerHighest;
    }
  }

  Color _avatarTextColor(String status) {
    switch (status) {
      case 'green':
        return cs.primary;
      case 'yellow':
        return cs.tertiary;
      default:
        return cs.onSurfaceVariant;
    }
  }

  Color _schemeStatusColor(String status) {
    switch (status) {
      case 'draft':
        return Colors.orange;
      case 'pending':
        return Colors.blue;
      case 'approved':
        return Colors.green;
      default:
        return cs.onSurfaceVariant;
    }
  }

  String _schemeStatusLabel(String status) {
    switch (status) {
      case 'draft':
        return 'Draft';
      case 'pending':
        return 'Pending';
      case 'approved':
        return 'Approved';
      default:
        return 'No Scheme';
    }
  }
}

// ---------------------------------------------------------------------------
// Pending Teachers Tab
// ---------------------------------------------------------------------------

class _PendingTeachersTab extends ConsumerStatefulWidget {
  final List<PendingTeacherData> pendingTeachers;
  final AuthStateData authData;

  const _PendingTeachersTab({
    required this.pendingTeachers,
    required this.authData,
  });

  @override
  ConsumerState<_PendingTeachersTab> createState() =>
      _PendingTeachersTabState();
}

class _PendingTeachersTabState extends ConsumerState<_PendingTeachersTab> {
  bool _isResending = false;

  Future<void> _resendPassword(PendingTeacherData teacher) async {
    setState(() => _isResending = true);
    try {
      await ref
          .read(authProvider.notifier)
          .resendTeacherPassword(
            email: teacher.email,
            teacherName: teacher.teacherName,
            role: teacher.role,
          );

      if (!mounted) return;
      showInfoToast(
        context: context,
        message: 'A new temporary password has been emailed.',
      );
      // Refresh to show updated temp_password
      ref.read(adminDashboardProvider.notifier).refresh();
    } on AuthException catch (e) {
      if (!mounted) return;
      showInfoToast(
        context: context,
        message: e.message,
      );
    } catch (e) {
      if (!mounted) return;
      showInfoToast(
        context: context,
        message: 'Failed to resend password. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Empty state
    if (widget.pendingTeachers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 64,
              color: cs.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'No pending teachers',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'All teachers have logged in.',
              style: textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(

      physics: (Platform.isAndroid || Platform.isIOS)
          ? const BouncingScrollPhysics()
          : null,
      padding: const EdgeInsets.only(bottom: 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              '${widget.pendingTeachers.length} teacher${widget.pendingTeachers.length != 1 ? 's' : ''} haven\'t logged in yet',
              style: textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),

          // Pending teacher cards
          ...widget.pendingTeachers.map((teacher) {
            return _buildPendingTeacherCard(
                context, cs, textTheme, teacher);
          }),
        ],
      ),
    );
  }

  Widget _buildPendingTeacherCard(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    PendingTeacherData teacher,
  ) {
    final initials = _getInitials(teacher.teacherName);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: avatar + name/email
          Row(
            children: [
              // Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.tertiary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      teacher.teacherName,
                      style: textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      teacher.email,
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

          // Temporary password row
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.key_rounded,
                  size: 16,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Temporary Password',
                        style: textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        teacher.tempPassword ?? '(not available)',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: cs.primary,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                // Copy button
                if (teacher.tempPassword != null)
                  IconButton(
                    icon: Icon(
                      Icons.copy_rounded,
                      size: 18,
                      color: cs.primary,
                    ),
                    tooltip: 'Copy password',
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: teacher.tempPassword!),
                      );
                      showInfoToast(
                        context: context,
                        message: 'Password copied to clipboard',
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Resend button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isResending
                  ? null
                  : () => _resendPassword(teacher),
              icon: _isResending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.email_rounded, size: 18),
              label: Text(_isResending
                  ? 'Resending...'
                  : 'Resend Email'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.primary,
                side: BorderSide(color: cs.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

// // Vault feature disabled — kept for reference
// // ---------------------------------------------------------------------------
// // Vault Approval Tab
// // ---------------------------------------------------------------------------
//
// class _VaultApprovalTab extends ConsumerWidget {
//   final AuthStateData authData;
//
//   const _VaultApprovalTab({required this.authData});
//
//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final cs = Theme.of(context).colorScheme;
//     final textTheme = Theme.of(context).textTheme;
//
//     // Tier gate: Standard+ required for vault approval queue visibility
//     final tier = authData.currentSchool?.subscriptionTier ?? 'free';
//     final approvedTiers = ['standard', 'elite'];
//     if (!approvedTiers.contains(tier.toLowerCase())) {
//       return Center(
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Icon(
//               Icons.lock_outline_rounded,
//               size: 64,
//               color: cs.onSurfaceVariant.withValues(alpha: 0.4),
//             ),
//             const SizedBox(height: 16),
//             Text(
//               'Vault approval queue requires a Standard or Elite subscription.',
//               textAlign: TextAlign.center,
//               style:
//                   textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant),
//             ),
//           ],
//         ),
//       );
//     }
//
//     return FutureBuilder(
//       future: ref.read(databaseProvider).vaultItemsDao.getPendingApproval(),
//       builder: (context, snapshot) {
//         if (snapshot.connectionState != ConnectionState.done) {
//           return const Center(child: CircularProgressIndicator());
//         }
//
//         final items = snapshot.data ?? [];
//
//         if (items.isEmpty) {
//           return Center(
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Icon(
//                   Icons.check_circle_outline_rounded,
//                   size: 64,
//                   color: cs.primary.withValues(alpha: 0.6),
//                 ),
//                 const SizedBox(height: 16),
//                 Text(
//                   'No pending approvals',
//                   style: textTheme.titleMedium,
//                 ),
//               ],
//             ),
//           );
//         }
//
//         return ListView.builder(
//           physics: (Platform.isAndroid || Platform.isIOS)
//               ? const BouncingScrollPhysics()
//               : null,
//           padding: const EdgeInsets.all(16),
//           itemCount: items.length,
//           itemBuilder: (context, index) {
//             final item = items[index];
//             return Container(
//               margin: const EdgeInsets.only(bottom: 12),
//               decoration: BoxDecoration(
//                 color: cs.surfaceContainerLow,
//                 borderRadius: BorderRadius.circular(8),
//                 border: Border.all(
//                   color: cs.outlineVariant.withValues(alpha: 0.2),
//                 ),
//               ),
//               padding: const EdgeInsets.all(16),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     item.title,
//                     style: textTheme.titleMedium?.copyWith(
//                       fontWeight: FontWeight.w700,
//                     ),
//                   ),
//                   const SizedBox(height: 4),
//                   Text(
//                     'By ${item.authorName} \u00b7 ${item.subject} \u00b7 ${item.classLevel}',
//                     style: textTheme.bodySmall,
//                   ),
//                   const SizedBox(height: 4),
//                   Text(
//                     item.description,
//                     maxLines: 2,
//                     overflow: TextOverflow.ellipsis,
//                     style: textTheme.bodyMedium,
//                   ),
//                   const SizedBox(height: 12),
//                   Row(
//                     mainAxisAlignment: MainAxisAlignment.end,
//                     children: [
//                       OutlinedButton(
//                         onPressed: () => _rejectItem(context, ref, item.id),
//                         style: OutlinedButton.styleFrom(
//                           foregroundColor: cs.error,
//                         ),
//                         child: const Text('Reject'),
//                       ),
//                       const SizedBox(width: 8),
//                       FilledButton(
//                         onPressed: () => _approveItem(context, ref, item.id),
//                         child: const Text('Approve'),
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//             );
//           },
//         );
//       },
//     );
//   }
//
//   Future<void> _approveItem(
//       BuildContext context, WidgetRef ref, int itemId) async {
//     await ref.read(databaseProvider).vaultItemsDao.approve(itemId);
//     if (context.mounted) {
//       showInfoToast(context: context, message: 'Item approved');
//     }
//   }
//
//   Future<void> _rejectItem(
//       BuildContext context, WidgetRef ref, int itemId) async {
//     final reason = await showDialog<String>(
//       context: context,
//       builder: (ctx) => const _RejectionDialog(),
//     );
//     if (reason != null && reason.isNotEmpty) {
//       await ref.read(databaseProvider).vaultItemsDao.reject(itemId, reason);
//       if (context.mounted) {
//         showInfoToast(context: context, message: 'Item rejected');
//       }
//     }
//   }
// }
//
// class _RejectionDialog extends ConsumerWidget {
//   const _RejectionDialog();
//
//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final controller = TextEditingController();
//     return AlertDialog(
//       shape: RoundedRectangleBorder(
//         borderRadius: BorderRadius.circular(8),
//       ),
//       title: const Text('Rejection Reason'),
//       content: TextField(
//         controller: controller,
//         decoration: const InputDecoration(
//           hintText: 'Enter reason for rejection...',
//         ),
//         maxLines: 3,
//       ),
//       actions: [
//         TextButton(
//           onPressed: () => Navigator.of(context).pop(),
//           child: const Text('Cancel'),
//         ),
//         FilledButton(
//           onPressed: () => Navigator.of(context).pop(controller.text),
//           child: const Text('Submit'),
//         ),
//       ],
//     );
//   }
// }

// ---------------------------------------------------------------------------
// Sync Health Tab
// ---------------------------------------------------------------------------

class _SyncHealthTab extends StatelessWidget {
  final List<TeacherAdminData> teachers;
  final AdminDashboardData dashboardData;
  final bool isWide;

  const _SyncHealthTab({
    required this.teachers,
    required this.dashboardData,
    required this.isWide,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (teachers.isEmpty) {
      return const Center(child: Text('No teacher data available.'));
    }

    // Summary counts
    final greenCount = teachers.where((t) => t.statusColor == 'green').length;
    final yellowCount = teachers.where((t) => t.statusColor == 'yellow').length;
    final redCount = teachers.where((t) => t.statusColor == 'red').length;
    final grayCount = teachers.where((t) => t.statusColor == 'gray').length;
    final totalTeachers = teachers.length;
    final syncPercent =
        totalTeachers > 0 ? ((greenCount / totalTeachers) * 100).round() : 0;

    return SingleChildScrollView(

      physics: (Platform.isAndroid || Platform.isIOS)
          ? const BouncingScrollPhysics()
          : null,
      padding: const EdgeInsets.only(bottom: 80),
      child: isWide
          ? _buildWideLayout(context, cs, textTheme, greenCount, yellowCount,
              redCount, grayCount, syncPercent, totalTeachers)
          : _buildNarrowLayout(context, cs, textTheme, greenCount, yellowCount,
              redCount, grayCount, syncPercent, totalTeachers),
    );
  }

  // Wide: two-column bento layout matching Stitch
  Widget _buildWideLayout(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    int greenCount,
    int yellowCount,
    int redCount,
    int grayCount,
    int syncPercent,
    int totalTeachers,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryCard(cs, textTheme, greenCount, yellowCount, redCount,
            grayCount, syncPercent, totalTeachers,
            isWide: true),
      ],
    );
  }

  // Narrow: stacked layout
  Widget _buildNarrowLayout(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    int greenCount,
    int yellowCount,
    int redCount,
    int grayCount,
    int syncPercent,
    int totalTeachers,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryCard(cs, textTheme, greenCount, yellowCount, redCount,
            grayCount, syncPercent, totalTeachers,
            isWide: false),

        // Per-teacher sync details
        const SizedBox(height: 16),
        ...teachers.map((teacher) => _buildTeacherSyncCard(
              context,
              cs,
              textTheme,
              teacher,
            )),
      ],
    );
  }

  Widget _buildSummaryCard(
    ColorScheme cs,
    TextTheme textTheme,
    int greenCount,
    int yellowCount,
    int redCount,
    int grayCount,
    int syncPercent,
    int totalTeachers, {
    required bool isWide,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.sync_rounded, size: 22, color: cs.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Sync Health Summary',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Sync percentage bar
          Row(
            children: [
              Flexible(
                child: Text(
                  '$syncPercent%',
                  style: textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.primary,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: syncPercent / 100,
                    minHeight: 8,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      syncPercent >= 80
                          ? cs.primary
                          : syncPercent >= 50
                              ? cs.tertiary
                              : cs.error,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Status counts in a row
          isWide
              ? Row(
                  children: [
                    _statusCountChip(
                        cs, textTheme, 'Synced', greenCount, cs.primary),
                    const SizedBox(width: 16),
                    _statusCountChip(
                        cs, textTheme, 'Warning', yellowCount, cs.tertiary),
                    const SizedBox(width: 16),
                    _statusCountChip(
                        cs, textTheme, 'Error', redCount, cs.error),
                    const SizedBox(width: 16),
                    _statusCountChip(cs, textTheme, 'Offline', grayCount,
                        cs.onSurfaceVariant),
                  ],
                )
              : Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _statusCountChip(
                        cs, textTheme, 'Synced', greenCount, cs.primary),
                    _statusCountChip(
                        cs, textTheme, 'Warning', yellowCount, cs.tertiary),
                    _statusCountChip(
                        cs, textTheme, 'Error', redCount, cs.error),
                    _statusCountChip(cs, textTheme, 'Offline', grayCount,
                        cs.onSurfaceVariant),
                  ],
                ),
          const SizedBox(height: 12),
          Text(
            '$totalTeachers teacher${totalTeachers != 1 ? 's' : ''} tracked',
            style: textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCountChip(
    ColorScheme cs,
    TextTheme textTheme,
    String label,
    int count,
    Color dotColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count $label',
            style: textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Teacher Sync Detail Card
  // ---------------------------------------------------------------
  Widget _buildTeacherSyncCard(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    TeacherAdminData teacher,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusDot(color: _statusColor(teacher.statusColor, cs)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  teacher.teacherName,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Last sync: ${teacher.lastSyncTime != null ? _formatTime(teacher.lastSyncTime!) : "Never"}',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Devices: ${teacher.deviceCount} \u00b7 '
                  'Pending: ${teacher.pendingSyncCount} \u00b7 '
                  'Conflicts: ${teacher.conflictCount}',
                  style: textTheme.bodySmall?.copyWith(
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

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _statusColor(String status, ColorScheme cs) {
    switch (status) {
      case 'green':
        return cs.primary;
      case 'yellow':
        return cs.tertiary;
      case 'red':
        return cs.error;
      default:
        return cs.onSurfaceVariant;
    }
  }
}

// ---------------------------------------------------------------------------
// Shared Helpers
// ---------------------------------------------------------------------------

class _StatusDot extends StatelessWidget {
  final Color color;

  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
