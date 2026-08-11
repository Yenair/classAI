import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/core/utils/platform_helper.dart';
import 'package:classai/core/theme/app_theme.dart';
import 'package:classai/core/widgets/conflict_banner.dart';
import 'package:classai/core/widgets/sync_indicator.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/sync_status_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/features/dashboard/providers/unresolved_conflicts_provider.dart';
import 'package:classai/features/dashboard/providers/dashboard_data_providers.dart';
import 'package:classai/features/settings/providers/theme_provider.dart';
import 'package:classai/core/services/payment_service.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/config_provider.dart';
import 'package:classai/core/widgets/upgrade_request_dialog.dart';
import 'package:classai/main.dart' show databaseProvider;

void _goToLessonsDeferred(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    context.go('/lessons');
  });
}

/// Root dashboard screen that routes to either [EditorLayout] or [ReaderLayout]
/// based on [PlatformHelper.isEditorMode].
///
/// Layout redesigned to match the Google Stitch design HTML.
/// - Editor (Tablet): Nav drawer + AppBar + Bento grid content
/// - Reader (Phone): AppBar + cards + rounded BottomNav
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  /// Shows a confirmation dialog when the system back button is pressed on the
  /// home route (`/`). If the user confirms, the app is closed.
  ///
  /// ESC (desktop) and system back (Android) while the dialog is open will
  /// dismiss the dialog instead of quitting, because the dialog sits on top of
  /// the navigator stack and gets popped first.
  void _onBackPressed(bool didPop) {
    if (didPop) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text('Quit ClassAI?'),
        content: const Text('Are you sure you want to quit the app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              SystemNavigator.pop();
            },
            child: const Text('Quit'),
          ),
        ],
      ),
    );
  }

  /// null = still loading, true = EditorLayout, false = ReaderLayout
  bool? _isEditorMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final isEditor = await PlatformHelper.isEditorMode(context);
      if (mounted) {
        setState(() => _isEditorMode = isEditor);
      }
      _resumePendingPayments();
    });
  }

  Future<void> _resumePendingPayments() async {
    try {
      final db = ref.read(databaseProvider);
      final pendingPayments = await db.paymentEventsDao.getUnconfirmed();
      if (pendingPayments.isEmpty || !mounted) return;

      final authData = ref.read(authProvider);
      final school = authData.currentSchool;
      final teacher = authData.currentTeacher;
      if (school == null || teacher == null) return;

      final paymentService = PaymentService(db);
      final schoolId = school.serverId ?? school.localId.toString();

      for (final payment in pendingPayments) {
        final confirmed = await paymentService.verifyPayment(
          payment.transactionReference,
        );
        if (!confirmed || !mounted) {
          continue;
        }
        await paymentService.confirmPayment(
          reference: payment.transactionReference,
          plan: payment.plan,
          schoolId: schoolId,
        );
        ref.read(authProvider.notifier).refreshSchoolFromDb();
        break;
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Platform gate: non-mobile platforms always use the editor layout
    if (!Platform.isAndroid && !Platform.isIOS) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) => _onBackPressed(didPop),
        child: const EditorLayout(),
      );
    }

    // Android: always use ReaderLayout (bottom-nav-only), never EditorLayout (side nav)
    if (Platform.isAndroid) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) => _onBackPressed(didPop),
        child: const ReaderLayout(),
      );
    }

    if (_isEditorMode == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onBackPressed(didPop),
      child: _isEditorMode! ? const EditorLayout() : const ReaderLayout(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  EDITOR LAYOUT (Tablet / Desktop)
//  Matches stitch_design_v2/dashboard_editor_tablet_12sp_min/code.html
// ═══════════════════════════════════════════════════════════════════════════

class EditorLayout extends ConsumerStatefulWidget {
  const EditorLayout({super.key});

  @override
  ConsumerState<EditorLayout> createState() => _EditorLayoutState();
}

class _EditorLayoutState extends ConsumerState<EditorLayout> {
  int _selectedIndex = 0;
  bool _isSidebarOpen = true;

  List<NavItem> get _navItems {
    final authData = ref.read(authProvider);
    final isAdmin = authData.currentTeacher?.role == 'admin';
    return [
      NavItem(icon: Icons.home_rounded, label: 'Home', route: null),
      NavItem(icon: Icons.menu_book_rounded, label: 'Lessons', route: '/lessons'),
      NavItem(icon: Icons.quiz_rounded, label: 'Exams', route: '/exams'),
      // NavItem(icon: Icons.inventory_2_rounded, label: 'Vault', route: '/vault'), // Vault feature disabled
      // Scheme of Work is admin-only — teachers plan their term via "Plan My
      // Term" on the Lessons list.
      if (isAdmin)
        NavItem(icon: Icons.calendar_month_rounded, label: 'Scheme of Work', route: '/scheme-of-work'),
      if (isAdmin)
        NavItem(icon: Icons.admin_panel_settings_rounded, label: 'Admin', route: '/admin'),
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncStatusProvider.notifier).refresh();
      ref.read(offlineCreditStateProvider.notifier).refresh();
      ref.read(unresolvedConflictsProvider.notifier).refresh();
    });
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

  void _showExamTypePopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.quiz_rounded),
              title: const Text('Individual Topic Exam'),
              subtitle: const Text('Create an exam for a single topic'),
              onTap: () {
                Navigator.of(ctx).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    context.push('/exams');
                  }
                });
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.assignment_rounded),
              title: const Text('Full-Term Exam'),
              subtitle: const Text('Combine multiple topics into one exam'),
              onTap: () {
                Navigator.of(ctx).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    context.push('/full-term-exam');
                  }
                });
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  String _greeting(String? teacherName) {
    final hour = DateTime.now().hour;
    final timeGreeting = hour < 12
        ? 'Good Morning'
        : hour < 17
            ? 'Good Afternoon'
            : 'Good Evening';
    final name = teacherName ?? 'Educator';
    return '$timeGreeting, $name';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final authData = ref.watch(authProvider);
    final themeMode = ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Navigation Drawer ───────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: _isSidebarOpen ? 288 : 72,
            color: cs.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              physics: (Platform.isAndroid || Platform.isIOS)
                  ? const BouncingScrollPhysics()
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  // Logo area — tapping toggles sidebar
                  InkWell(
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    onTap: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: _isSidebarOpen ? 24 : 12,
                      ),
                      child: _isSidebarOpen
                          ? Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: cs.primaryContainer,
                                    borderRadius: BorderRadius.circular(
                                      AppTheme.radiusFull,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.person_rounded,
                                    color: cs.onPrimaryContainer,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          'ClassAI',
                                          style: theme.textTheme.headlineMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: cs.primary,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        'Nigerian Academic Partner',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Center(
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer,
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusFull,
                                  ),
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
                  const SizedBox(height: 32),
                // Nav items
                ...List.generate(_navItems.length, (index) {
                  final item = _navItems[index];
                  final isActive = index == _selectedIndex;
                  final isExamsNav = item.label == 'Exams';
                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: _isSidebarOpen ? 12 : 8,
                      vertical: 4,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusFull,
                        ),
                        onTap: () {
                          setState(() => _selectedIndex = index);
                          if (isExamsNav) {
                            _showExamTypePopup(context);
                          } else if (item.route != null) {
                            final route = item.route!;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (context.mounted) {
                                context.push(route);
                              }
                            });
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          transform: isActive
                              ? Matrix4.translationValues(4.0, 0.0, 0.0)
                              : Matrix4.identity(),
                          padding: EdgeInsets.symmetric(
                            horizontal: _isSidebarOpen ? 16 : 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? cs.secondaryFixed
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusFull,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: _isSidebarOpen
                                ? MainAxisAlignment.start
                                : MainAxisAlignment.center,
                            children: [
                              Icon(
                                item.icon,
                                size: 24,
                                color: isActive
                                    ? cs.onSecondaryFixed
                                    : cs.onSurfaceVariant,
                              ),
                              if (_isSidebarOpen) ...[
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    item.label,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style:
                                        theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: isActive
                                          ? cs.onSecondaryFixed
                                          : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
            ),
          ),

          // ── Main Content Area ───────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // ── TopAppBar ──────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingMarginTablet,
                    vertical: 8,
                  ),
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
                      Flexible(
                        child: Text(
                          'Dashboard',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Spacer(),
                      // Sync indicator (Stitch green dot style)
                      const _SyncChip(),
                      const SizedBox(width: 8),
                      // Offline credit chip
                      _OfflineCreditChip(visible: ref.watch(isOfflineProvider)),
                      const SizedBox(width: 8),
                      // Login button — only visible for guest users
                      if (authData.currentTeacher == null)
                        IconButton(
                          icon: const Icon(Icons.login_rounded),
                          tooltip: 'Sign in',
                          onPressed: () => context.push('/login'),
                          style: IconButton.styleFrom(
                            foregroundColor: cs.primary,
                          ),
                        ),
                      // Profile popup
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          switch (value) {
                            case 'settings':
                              context.push('/settings');
                            case 'logout':
                              _showLogoutConfirmation();
                            case 'theme_light':
                              ref.read(themeProvider.notifier).setTheme(ThemeMode.light);
                            case 'theme_dark':
                              ref.read(themeProvider.notifier).setTheme(ThemeMode.dark);
                            case 'theme_system':
                              ref.read(themeProvider.notifier).setTheme(ThemeMode.system);
                          }
                        },
                        offset: const Offset(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                        ),
                        itemBuilder: (context) {
                          final teacher = authData.currentTeacher;
                          return [
                            // ── Teacher info header ──
                            PopupMenuItem<String>(
                              enabled: false,
                              child: SizedBox(
                                width: 200,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      teacher?.teacherName ?? 'Educator',
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      teacher?.email ?? '',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const PopupMenuDivider(),
                            // ── Theme selector ──
                            PopupMenuItem<String>(
                              enabled: false,
                              child: Text(
                                'Theme',
                                style: theme.textTheme.labelMedium?.copyWith(
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
                            // ── Settings ──
                            const PopupMenuItem<String>(
                              value: 'settings',
                              child: ListTile(
                                leading: Icon(Icons.settings_rounded),
                                title: Text('Settings'),
                                contentPadding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            // ── Logout ──
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
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusFull,
                            ),
                          ),
                          child: Icon(
                            Icons.person_rounded,
                            size: 20,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Conflict Banner ────────────────────────────────
                const ConflictBanner(),

                // ── Announcement Banner ──────────────────────────────
                const _AnnouncementBanner(),

                // ── Free Plan Banner ──────────────────────────────
                if ((authData.currentSchool?.subscriptionTier ?? 'free').toLowerCase() == 'free')
                  _FreePlanBanner(
                    cs: cs,
                    theme: theme,
                    onUpgrade: () {
                      if (authData.currentTeacher?.role == 'admin') {
                        context.push('/payment');
                      } else {
                        showUpgradeRequestDialog(context, ref, requestedTier: 'elite');
                      }
                    },
                  ),

                // ── Canvas ─────────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(

                    physics: (Platform.isAndroid || Platform.isIOS)
                        ? const BouncingScrollPhysics()
                        : null,
                    padding: const EdgeInsets.all(
                      AppTheme.spacingMarginTablet,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1400),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Quick Actions Header
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _greeting(authData.currentTeacher?.teacherName),
                                        style: theme
                                            .textTheme.headlineMedium
                                            ?.copyWith(
                                              color: cs.primary,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Here's your academic overview for today.",
                                        style: theme
                                            .textTheme.bodyLarge
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Teacher-only action buttons — hidden for admins
                                // (redirect already blocks admins from this screen,
                                //  this is defense-in-depth)
                                if (authData.currentTeacher?.role != 'admin')
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: [
                                      _ActionButton(
                                        icon: Icons.add_rounded,
                                        label: 'Create Lesson',
                                        isPrimary: true,
                                        cs: cs,
                                        theme: theme,
                                        onTap: () =>
                                            context.push('/lesson-editor'),
                                      ),
                                      _ActionButton(
                                        icon: Icons.assignment_rounded,
                                        label: 'Generate Exam',
                                        isPrimary: false,
                                        cs: cs,
                                        theme: theme,
                                        onTap: () =>
                                            context.push('/exam-editor'),
                                      ),
                                    ],
                                  ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // Bento Grid
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isWide = constraints.maxWidth >= 900;
                                if (isWide) {
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Left column (span 2)
                                      Expanded(
                                        flex: 2,
                                        child: _RecentLessonsSection(
                                          cs: cs,
                                          theme: theme,
                                        ),
                                      ),
                                      const SizedBox(width: 24),
                                      // Right column
                                      SizedBox(
                                        width: 360,
                                        child: _RightColumn(
                                          cs: cs,
                                          theme: theme,
                                        ),
                                      ),
                                    ],
                                  );
                                } else {
                                  return Column(
                                    children: [
                                      _RecentLessonsSection(
                                        cs: cs,
                                        theme: theme,
                                      ),
                                      const SizedBox(height: 24),
                                      _RightColumn(cs: cs, theme: theme),
                                    ],
                                  );
                                }
                              },
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
}

// ═══════════════════════════════════════════════════════════════════════════
//  EDITOR SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class NavItem {
  const NavItem({
    required this.icon,
    required this.label,
    this.route,
  });
  final IconData icon;
  final String label;
  final String? route;
}

class _SyncChip extends ConsumerWidget {
  const _SyncChip();

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

class _OfflineCreditChip extends ConsumerWidget {
  const _OfflineCreditChip({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!visible) return const SizedBox.shrink();

    final offlineCreditData = ref.watch(offlineCreditStateProvider);
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () =>
            _showOfflineCreditInfo(context, ref, offlineCreditData, cs, theme),
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_open_rounded,
                size: 20,
                color: cs.primary,
              ),
              const SizedBox(width: 8),
              Text(
                offlineCreditData.loading
                    ? '…'
                    : '${offlineCreditData.currentOfflineCredits}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOfflineCreditInfo(
    BuildContext context,
    WidgetRef ref,
    OfflineCreditStateData offlineCreditData,
    ColorScheme cs,
    ThemeData theme,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sheet handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Title row
              Row(
                children: [
                  Icon(Icons.lock_open_rounded, color: cs.primary, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Offline Credits',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Offline credits let you access lessons, exams, and '
                'content even without an internet connection. '
                'Each unlock uses 1 credit.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              _OfflineCreditInfoRow(
                label: 'Available Offline Credits',
                value: offlineCreditData.loading
                    ? '…'
                    : '${offlineCreditData.currentOfflineCredits}',
                cs: cs,
                theme: theme,
              ),
              const SizedBox(height: 12),
              _OfflineCreditInfoRow(
                label: 'Tier',
                value: offlineCreditData.tierName,
                cs: cs,
                theme: theme,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineCreditInfoRow extends StatelessWidget {
  const _OfflineCreditInfoRow({
    required this.label,
    required this.value,
    required this.cs,
    required this.theme,
  });

  final String label;
  final String value;
  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.65),
              overflow: TextOverflow.clip,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
              overflow: TextOverflow.clip,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isPrimary,
    required this.cs,
    required this.theme,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isPrimary;
  final ColorScheme cs;
  final ThemeData theme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        child: Container(
          height: AppTheme.touchTarget,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: isPrimary ? cs.primary : cs.surfaceContainer,
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            border: isPrimary
                ? null
                : Border.all(color: cs.outlineVariant),
            boxShadow: isPrimary
                ? [
                    BoxShadow(
                      color: cs.onSurface.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isPrimary ? cs.onPrimary : cs.primary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isPrimary ? cs.onPrimary : cs.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentLessonsSection extends ConsumerWidget {
  const _RecentLessonsSection({required this.cs, required this.theme});
  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessonsAsync = ref.watch(recentLessonsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'Recent Lessons',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: cs.primary,
                  overflow: TextOverflow.clip,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _goToLessonsDeferred(context),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'View All',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        lessonsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Text(
            'Could not load lessons.',
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
          ),
          data: (lessons) {
            if (lessons.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'No lessons yet',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final sortedLessons = [...lessons]
                  ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                final twoColumns = constraints.maxWidth >= 600;
                final displayed = sortedLessons.take(4).toList();
                if (twoColumns) {
                  final row1 = displayed.take(2).toList();
                  final row2 = displayed.length > 2
                      ? displayed.skip(2).take(2).toList()
                      : <Lesson>[];
                  return Column(
                    children: [
                      Row(
                        children: row1
                            .map(
                              (lesson) => Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: row1.last == lesson ? 0 : 8,
                                  ),
                                  child: _LessonCard(
                                    icon: Icons.menu_book_rounded,
                                    iconColor: cs.primary,
                                    title: lesson.topic.isNotEmpty
                                        ? lesson.topic
                                        : lesson.subject,
                                    subtitle:
                                        '${lesson.classLevel} • ${lesson.subject}',
                                    status: lesson.status == 'completed' ? 'Completed' : 'Draft',
                                      statusColor: cs.primary,
                                      statusBg: cs.primary.withValues(alpha: 0.1),
                                      timeAgo: 'Updated ${_timeAgo(lesson.updatedAt)}',
                                      cs: cs,
                                      theme: theme,
                                      onTap: () => context.push('/lessons/${lesson.id}'),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                      ),
                      if (row2.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: row2
                              .map(
                                (lesson) => Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: row2.last == lesson ? 0 : 8,
                                    ),
                                    child: _LessonCard(
                                      icon: Icons.menu_book_rounded,
                                      iconColor: cs.tertiary,
                                      title: lesson.topic.isNotEmpty
                                          ? lesson.topic
                                          : lesson.subject,
                                      subtitle:
                                          '${lesson.classLevel} • ${lesson.subject}',
                                      status: lesson.status == 'completed' ? 'Completed' : 'Draft',
                                      statusColor: cs.onSurfaceVariant,
                                      statusBg: cs.surfaceContainerHighest,
                                      timeAgo:
                                          'Updated ${_timeAgo(lesson.updatedAt)}',
                                      cs: cs,
                                      theme: theme,
                                      onTap: () => context.push('/lessons/${lesson.id}'),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  );
                } else {
                  return Column(
                    children: displayed
                        .map(
                          (lesson) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _LessonCard(
                              icon: Icons.menu_book_rounded,
                              iconColor: cs.primary,
                              title: lesson.topic.isNotEmpty
                                  ? lesson.topic
                                  : lesson.subject,
                              subtitle:
                                  '${lesson.classLevel} • ${lesson.subject}',
                              status: lesson.status == 'completed' ? 'Completed' : 'Draft',
                              statusColor: cs.primary,
                              statusBg: cs.primary.withValues(alpha: 0.1),
                              timeAgo: 'Updated ${_timeAgo(lesson.updatedAt)}',
                              cs: cs,
                              theme: theme,
                              onTap: () => context.push('/lessons/${lesson.id}'),
                            ),
                          ),
                        )
                        .toList(),
                  );
                }
              },
            );
          },
        ),
      ],
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.statusColor,
    required this.statusBg,
    required this.timeAgo,
    required this.cs,
    required this.theme,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String status;
  final Color statusColor;
  final Color statusBg;
  final String timeAgo;
  final ColorScheme cs;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                      ),
                      child: Icon(icon, color: iconColor, size: 24),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: cs.primary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.outline,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.only(top: 16),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          timeAgo,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            overflow: TextOverflow.clip,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: cs.primary,
                      ),
                    ],
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

class _ReaderTotalOverviewPanel extends ConsumerWidget {
  const _ReaderTotalOverviewPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final lessonCountAsync = ref.watch(lessonCountProvider);
    final examCountAsync = ref.watch(examCountProvider);
    final conflictCount = ref.watch(unresolvedConflictsProvider);

    final lessonData = lessonCountAsync.asData?.value;
    final examData = examCountAsync.asData?.value;

    final lessonLabel = lessonData != null
        ? '${lessonData.total} (${lessonData.secondaryCount} completed)'
        : '...';
    final examLabel = examData != null
        ? '${examData.total} (${examData.secondaryCount} unlocked)'
        : '...';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, color: cs.primary, size: 22),
              const SizedBox(width: 10),
              Text(
                'Total Overview',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          _OverviewStatRow(
            icon: Icons.menu_book,
            label: 'Lessons',
            value: lessonCountAsync.isLoading ? '...' : lessonLabel,
            cs: cs,
            theme: theme,
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          _OverviewStatRow(
            icon: Icons.quiz,
            label: 'Exams',
            value: examCountAsync.isLoading ? '...' : examLabel,
            cs: cs,
            theme: theme,
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          _OverviewStatRow(
            icon: Icons.warning,
            label: 'Conflicts',
            value: '$conflictCount',
            cs: cs,
            theme: theme,
          ),
        ],
      ),
    );
  }
}

class _OverviewStatRow extends StatelessWidget {
  const _OverviewStatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.cs,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final String value;
  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          ),
          child: Icon(icon, color: cs.primary, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RightColumn extends ConsumerWidget {
  const _RightColumn({required this.cs, required this.theme});
  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessonCountAsync = ref.watch(lessonCountProvider);
    final examCountAsync = ref.watch(examCountProvider);
    final conflictCount = ref.watch(unresolvedConflictsProvider);

    final lessonData = lessonCountAsync.asData?.value;
    final examData = examCountAsync.asData?.value;

    final lessonCountLabel = lessonData != null
        ? '${lessonData.total} (${lessonData.secondaryCount} completed)'
        : '...';
    final examCountLabel = examData != null
        ? '${examData.total} (${examData.secondaryCount} unlocked)'
        : '...';

    return Column(
      children: [
        // Stats Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total Overview',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: cs.onPrimary,
                ),
              ),
              const SizedBox(height: 24),
              // Lessons stat
              Container(
                padding: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: cs.onPrimary.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LESSONS CREATED'.toUpperCase(),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onPrimary.withValues(alpha: 0.7),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lessonCountAsync.isLoading ? '...' : lessonCountLabel,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: cs.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Exams stat
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EXAMS GENERATED'.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: cs.onPrimary.withValues(alpha: 0.7),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        examCountAsync.isLoading ? '...' : examCountLabel,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: cs.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'CONFLICTS RESOLVED'.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onPrimary.withValues(alpha: 0.7),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$conflictCount',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: cs.onPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _CurrentWeekProgressCard(),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  READER LAYOUT (Phone)
//  Matches stitch_design_v2/dashboard_reader_phone/code.html
// ═══════════════════════════════════════════════════════════════════════════

// Providers (recentLessonsProvider, lessonCountProvider, examCountProvider,
// todayLessonCountProvider, lastUpdatedLessonProvider, CountData) are
// defined in lib/features/dashboard/providers/dashboard_data_providers.dart.

class CurrentWeekProgressData {
  final int weekNumber;
  final String topic;
  final int completedLessons;

  const CurrentWeekProgressData({
    required this.weekNumber,
    required this.topic,
    required this.completedLessons,
  });
}

final currentWeekProgressProvider =
    FutureProvider<CurrentWeekProgressData?>((ref) async {
  final db = ref.read(databaseProvider);
  final authData = ref.read(authProvider);
  final teacher = authData.currentTeacher;
  final teacherId = teacher?.localId;
  final teacherServerId = teacher?.serverId;
  final schoolServerId = authData.currentSchool?.serverId;

  if (teacherId == null || teacherServerId == null || schoolServerId == null) {
    return null;
  }

  final teacherLessons = await db.lessonsDao.getAllForTeacher(teacherServerId, schoolServerId);
  if (teacherLessons.isEmpty) return null;

  final activeWeek = teacherLessons
      .map((lesson) => lesson.weekNumber ?? lesson.week)
      .reduce((a, b) => a > b ? a : b);

  final schemes = await db.schemeOfWorkDao.getSaved();
  final matchingSchemes = schemes
      .where((scheme) => scheme.teacherId == teacherId)
      .toList()
    ..sort((a, b) => a.weekNumber.compareTo(b.weekNumber));
  if (matchingSchemes.isEmpty) return null;

  SchemeOfWorkData schemeForWeek = matchingSchemes.first;
  for (final scheme in matchingSchemes) {
    if (scheme.weekNumber == activeWeek) {
      schemeForWeek = scheme;
      break;
    }
    if (scheme.weekNumber <= activeWeek) {
      schemeForWeek = scheme;
    }
  }

  final completedLessons = teacherLessons
      .where((lesson) =>
          (lesson.weekNumber ?? lesson.week) == schemeForWeek.weekNumber &&
          lesson.status == 'completed')
      .length;

  return CurrentWeekProgressData(
    weekNumber: schemeForWeek.weekNumber,
    topic: schemeForWeek.topic,
    completedLessons: completedLessons,
  );
});

class ReaderLayout extends ConsumerStatefulWidget {
  const ReaderLayout({super.key});

  @override
  ConsumerState<ReaderLayout> createState() => _ReaderLayoutState();
}

class _ReaderLayoutState extends ConsumerState<ReaderLayout> {
  int _selectedIndex = 1; // Lessons is active by default in the HTML

  /// Bottom-nav destinations. The Scheme of Work tab is admin-only — teachers
  /// plan their term via "Plan My Term" on the Lessons list.
  List<_ReaderNavSpec> get _navSpecs {
    final isAdmin = ref.read(authProvider).currentTeacher?.role == 'admin';
    final specs = <_ReaderNavSpec>[
      const _ReaderNavSpec(icon: Icons.home_rounded, label: 'Home', route: 'home'),
      const _ReaderNavSpec(
          icon: Icons.menu_book_rounded, label: 'Lessons', route: '/lessons', isFilled: true),
      const _ReaderNavSpec(icon: Icons.quiz_rounded, label: 'Exams', route: 'exams'),
      if (isAdmin)
        const _ReaderNavSpec(
            icon: Icons.calendar_month_rounded, label: 'Scheme of Work', route: '/scheme-of-work'),
      const _ReaderNavSpec(icon: Icons.more_horiz_rounded, label: 'More', route: '/settings'),
    ];
    for (var i = 0; i < specs.length; i++) {
      specs[i] = _ReaderNavSpec(
        icon: specs[i].icon,
        label: specs[i].label,
        route: specs[i].route,
        isFilled: specs[i].isFilled,
        index: i,
      );
    }
    return specs;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncStatusProvider.notifier).refresh();
      ref.read(offlineCreditStateProvider.notifier).refresh();
      ref.read(unresolvedConflictsProvider.notifier).refresh();
    });
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

  void _showReaderCreditInfo(
    BuildContext context,
    WidgetRef ref,
    OfflineCreditStateData offlineCreditData,
    ColorScheme cs,
    ThemeData theme,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sheet handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Title row
              Row(
                children: [
                  Icon(Icons.lock_open_rounded, color: cs.primary, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Offline Credits',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Offline credits let you access lessons, exams, and '
                'content even without an internet connection. '
                'Each unlock uses 1 credit.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              _OfflineCreditInfoRow(
                label: 'Available Offline Credits',
                value: offlineCreditData.loading
                    ? '…'
                    : '${offlineCreditData.currentOfflineCredits}',
                cs: cs,
                theme: theme,
              ),
              const SizedBox(height: 12),
              _OfflineCreditInfoRow(
                label: 'Tier',
                value: offlineCreditData.tierName,
                cs: cs,
                theme: theme,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final authData = ref.watch(authProvider);
    final themeMode = ref.watch(themeProvider);
    final syncData = ref.watch(syncStatusProvider);
    final offlineCreditData = ref.watch(offlineCreditStateProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMarginMobile,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              bottom: BorderSide(
                color: cs.surfaceContainer.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                // Profile popup (left side)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'settings':
                        context.push('/settings');
                      case 'logout':
                        _showLogoutConfirmation();
                      case 'theme_light':
                        ref.read(themeProvider.notifier).setTheme(ThemeMode.light);
                      case 'theme_dark':
                        ref.read(themeProvider.notifier).setTheme(ThemeMode.dark);
                      case 'theme_system':
                        ref.read(themeProvider.notifier).setTheme(ThemeMode.system);
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
                                teacher?.teacherName ?? 'Educator',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                teacher?.email ?? '',
                                style: theme.textTheme.bodySmall?.copyWith(
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
                          style: theme.textTheme.labelMedium?.copyWith(
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
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusFull,
                      ),
                    ),
                    child: Icon(
                      Icons.person_rounded,
                      size: 20,
                      color: cs.outline,
                    ),
                  ),
                ),
                // Centered title
                Expanded(
                  child: Center(
                    child: Text(
                      'ClassAI',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ),
                // Sync status indicator (live from syncStatusProvider)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: syncData.status == SyncStatus.syncing
                        ? null
                        : () => ref.read(syncStatusProvider.notifier).syncNow(),
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: syncData.status == SyncStatus.synced
                                  ? cs.primary
                                  : syncData.status == SyncStatus.syncing
                                      ? cs.primary
                                      : syncData.status == SyncStatus.error
                                          ? cs.error
                                          : cs.onSurfaceVariant,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            statusLabel(syncData.status),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: cs.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Login button — only visible for guest users
                if (authData.currentTeacher == null)
                  IconButton(
                    icon: const Icon(Icons.login_rounded),
                    tooltip: 'Sign in',
                    onPressed: () => context.push('/login'),
                    style: IconButton.styleFrom(
                      foregroundColor: cs.primary,
                    ),
                  ),
                // Credit chip (live from offlineCreditStateProvider)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _showReaderCreditInfo(
                      context,
                      ref,
                      offlineCreditData,
                      cs,
                      theme,
                    ),
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusFull,
                        ),
                      ),
                      child: Text(
                        offlineCreditData.loading
                            ? '…'
                            : '${offlineCreditData.currentOfflineCredits}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Announcement Banner ──────────────────────────────
          const _AnnouncementBanner(),

          // ── Free Plan Banner ──────────────────────────────
          if ((authData.currentSchool?.subscriptionTier ?? 'free').toLowerCase() == 'free')
            _FreePlanBanner(
              cs: cs,
              theme: theme,
              onUpgrade: () {
                if (authData.currentTeacher?.role == 'admin') {
                  context.push('/payment');
                } else {
                  showUpgradeRequestDialog(context, ref, requestedTier: 'elite');
                }
              },
            ),
          Expanded(
            child: SingleChildScrollView(
              physics: (Platform.isAndroid || Platform.isIOS)
                  ? const BouncingScrollPhysics()
                  : null,
              padding: const EdgeInsets.all(AppTheme.spacingMarginMobile),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    "Today's Lessons",
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Continue your reading materials for today's classes.",
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _ReaderTotalOverviewPanel(),
                  const SizedBox(height: 24),
                  _RecentLessonsSection(cs: cs, theme: theme),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _ReaderBottomNav(
        selectedIndex: _selectedIndex,
        cs: cs,
        theme: theme,
        destinations: _navSpecs,
        onTap: (spec) {
          setState(() => _selectedIndex = spec.index);
          _onNavDestination(context, spec.route);
        },
      ),
    );
  }

  void _onNavDestination(BuildContext context, String route) {
    switch (route) {
      case 'home':
        break; // Home (already here)
      case '/lessons':
        _goToLessonsDeferred(context);
        break;
      case 'exams':
        _showReaderExamPopup(context);
        break;
      case '/scheme-of-work':
        context.go('/scheme-of-work');
        break;
      case '/settings':
        context.go('/settings');
        break;
    }
  }

  void _showReaderExamPopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.quiz_rounded),
              title: const Text('Individual Topic Exam'),
              subtitle: const Text('Create an exam for a single topic'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.go('/exams');
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.assignment_rounded),
              title: const Text('Full-Term Exam'),
              subtitle: const Text('Combine multiple topics into one exam'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/full-term-exam');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _ReaderNavSpec {
  final IconData icon;
  final String label;
  final String route;
  final bool isFilled;
  final int index;

  const _ReaderNavSpec({
    required this.icon,
    required this.label,
    required this.route,
    this.isFilled = false,
    this.index = 0,
  });
}

class _ReaderBottomNav extends StatelessWidget {
  const _ReaderBottomNav({
    required this.selectedIndex,
    required this.cs,
    required this.theme,
    required this.destinations,
    required this.onTap,
  });

  final int selectedIndex;
  final ColorScheme cs;
  final ThemeData theme;
  final List<_ReaderNavSpec> destinations;
  final ValueChanged<_ReaderNavSpec> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      padding: const EdgeInsets.only(top: 4, left: 8, right: 8, bottom: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppTheme.radiusFull),
          topRight: Radius.circular(AppTheme.radiusFull),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.onSurface.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          for (final spec in destinations)
            Expanded(child: _BottomNavItem(
              icon: spec.icon,
              label: spec.label,
              isActive: selectedIndex == spec.index,
              isFilled: spec.isFilled,
              cs: cs,
              theme: theme,
              onTap: () => onTap(spec),
            )),
        ],
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isFilled,
    required this.cs,
    required this.theme,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final bool isFilled;
  final ColorScheme cs;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (isFilled && isActive) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: cs.onSecondaryContainer),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentWeekProgressCard extends ConsumerWidget {
  const _CurrentWeekProgressCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(currentWeekProgressProvider);
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return progressAsync.when(
      loading: () => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
        child: Text(
          'No active scheme',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
      data: (progress) {
        if (progress == null) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
            ),
            child: Text(
              'No active scheme',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Upcoming Schedule',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Week ${progress.weekNumber}: ${progress.topic}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${progress.completedLessons} completed lesson${progress.completedLessons == 1 ? '' : 's'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Shows an announcement banner from remote config when [announcementText] is
/// non‑empty.
class _AnnouncementBanner extends ConsumerWidget {
  const _AnnouncementBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configServiceProvider);
    final text = config.announcementText;
    if (text.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.6),
        border: Border(
          bottom: BorderSide(
            color: cs.primary.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.campaign_rounded, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stitch-style banner displayed on the Free plan.
///
/// Renders an amber/yellow bar with an "Upgrade" CTA.  Disappears
/// reactively when the school's [subscriptionTier] changes away from
/// `'free'` because the widget is guarded by the caller with the same
/// condition from the same authProvider watch.
class _FreePlanBanner extends StatelessWidget {
  const _FreePlanBanner({
    required this.cs,
    required this.theme,
    required this.onUpgrade,
  });

  final ColorScheme cs;
  final ThemeData theme;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        border: Border(
          bottom: BorderSide(color: Colors.amber.shade400, width: 1.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.amber.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "You're on the Free plan. Upgrade to unlock more features.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onUpgrade,
            style: TextButton.styleFrom(
              foregroundColor: Colors.amber.shade800,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }
}

