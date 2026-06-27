import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:classai/core/utils/platform_helper.dart';
import 'package:classai/core/theme/app_theme.dart';
import 'package:classai/core/widgets/conflict_banner.dart';
import 'package:classai/core/widgets/sync_indicator.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/sync_status_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/features/dashboard/providers/unresolved_conflicts_provider.dart';
import 'package:classai/features/settings/providers/theme_provider.dart';
import 'package:classai/core/services/payment_service.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/main.dart' show databaseProvider;

void _goToLessonsDeferred(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    context.push('/lessons');
  });
}

void _goToLessonEditorDeferred(BuildContext context, int lessonId) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    context.push('/lessons/$lessonId');
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

      final dio = Dio(BaseOptions(
        baseUrl: '',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      ));
      final paymentService = PaymentService(db, dio);
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
      NavItem(icon: Icons.inventory_2_rounded, label: 'Vault', route: '/vault'),
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
      ref.read(creditStateProvider.notifier).refresh();
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
            width: _isSidebarOpen ? 288 : 0,
            color: cs.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              physics: (Platform.isAndroid || Platform.isIOS)
                  ? const BouncingScrollPhysics()
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                // Logo area
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
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
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                            Text(
                              'Nigerian Academic Partner',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Nav items
                ...List.generate(_navItems.length, (index) {
                  final item = _navItems[index];
                  final isActive = index == _selectedIndex;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
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
                          if (item.route != null) {
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
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
                            children: [
                              Icon(
                                item.icon,
                                size: 24,
                                color: isActive
                                    ? cs.onSecondaryFixed
                                    : cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 16),
                              Text(
                                item.label,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight:
                                      isActive ? FontWeight.w600 : FontWeight.w500,
                                  color: isActive
                                      ? cs.onSecondaryFixed
                                      : cs.onSurfaceVariant,
                                ),
                              ),
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
                      IconButton(
                        onPressed: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
                        icon: Icon(_isSidebarOpen ? Icons.menu_open_rounded : Icons.menu_rounded),
                        tooltip: _isSidebarOpen ? 'Close sidebar' : 'Open sidebar',
                        style: IconButton.styleFrom(
                          foregroundColor: cs.onSurfaceVariant,
                        ),
                      ),
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
                      // Credit chip
                      const _CreditChip(),
                      const SizedBox(width: 8),
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

                // ── Free Plan Banner ──────────────────────────────
                if (authData.currentSchool?.subscriptionTier == 'free')
                  _FreePlanBanner(
                    cs: cs,
                    theme: theme,
                    onUpgrade: () => context.push('/payment'),
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

                            // ── Today at a Glance ──────────────────────
                            const _TodayAtAGlanceStrip(),

                            const SizedBox(height: 24),

                            // ── Resume Last Lesson ─────────────────────
                            _ResumeLessonCard(cs: cs, theme: theme),

                            const SizedBox(height: 32),

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

class _CreditChip extends ConsumerWidget {
  const _CreditChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditData = ref.watch(creditStateProvider);
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showCreditInfo(context, ref, creditData, cs, theme),
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
                creditData.loading ? '…' : '${creditData.currentCredits}',
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

  void _showCreditInfo(
    BuildContext context,
    WidgetRef ref,
    CreditStateData creditData,
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
              _CreditInfoRow(
                label: 'Available Credits',
                value: creditData.loading
                    ? '…'
                    : '${creditData.currentCredits}',
                cs: cs,
                theme: theme,
              ),
              const SizedBox(height: 12),
              _CreditInfoRow(
                label: 'Tier',
                value: creditData.tierName,
                cs: cs,
                theme: theme,
              ),
              if (creditData.nextRefillTime != null) ...[
                const SizedBox(height: 12),
                _CreditInfoRow(
                  label: 'Next Refill',
                  value: DateFormat('MMM d, yyyy')
                      .format(creditData.nextRefillTime!),
                  cs: cs,
                  theme: theme,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CreditInfoRow extends StatelessWidget {
  const _CreditInfoRow({
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
                final twoColumns = constraints.maxWidth >= 600;
                final displayed = lessons.take(4).toList();
                if (twoColumns) {
                  final row1 = displayed.take(2).toList();
                  final row2 = displayed.length > 2 ? displayed.skip(2).take(2).toList() : <Lesson>[];
                  return Column(
                    children: [
                      Row(
                        children: row1.map((lesson) => Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: row1.last == lesson ? 0 : 8,
                            ),
                            child: _LessonCard(
                              lessonId: lesson.id,
                              icon: Icons.menu_book_rounded,
                              iconColor: cs.primary,
                              title: lesson.topic.isNotEmpty ? lesson.topic : lesson.subject,
                              subtitle: '${lesson.classLevel} \u2022 ${lesson.subject}',
                              status: lesson.difficulty,
                              statusColor: cs.primary,
                              statusBg: cs.primary.withValues(alpha: 0.1),
                              timeAgo: 'Updated ${_timeAgo(lesson.updatedAt)}',
                              cs: cs,
                              theme: theme,
                            ),
                          ),
                        )).toList(),
                      ),
                      if (row2.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: row2.map((lesson) => Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: row2.last == lesson ? 0 : 8,
                              ),
                              child: _LessonCard(
                                lessonId: lesson.id,
                                icon: Icons.menu_book_rounded,
                                iconColor: cs.tertiary,
                                title: lesson.topic.isNotEmpty ? lesson.topic : lesson.subject,
                                subtitle: '${lesson.classLevel} \u2022 ${lesson.subject}',
                                status: lesson.difficulty,
                                statusColor: cs.onSurfaceVariant,
                                statusBg: cs.surfaceContainerHighest,
                                timeAgo: 'Updated ${_timeAgo(lesson.updatedAt)}',
                                cs: cs,
                                theme: theme,
                              ),
                            ),
                          )).toList(),
                        ),
                      ],
                    ],
                  );
                } else {
                  return Column(
                    children: displayed.map((lesson) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _LessonCard(
                        lessonId: lesson.id,
                        icon: Icons.menu_book_rounded,
                        iconColor: cs.primary,
                        title: lesson.topic.isNotEmpty ? lesson.topic : lesson.subject,
                        subtitle: '${lesson.classLevel} \u2022 ${lesson.subject}',
                        status: lesson.difficulty,
                        statusColor: cs.primary,
                        statusBg: cs.primary.withValues(alpha: 0.1),
                        timeAgo: 'Updated ${_timeAgo(lesson.updatedAt)}',
                        cs: cs,
                        theme: theme,
                      ),
                    )).toList(),
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
    required this.lessonId,
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
  });

  final int lessonId;
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
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
            style: theme.textTheme.titleLarge?.copyWith(
              color: cs.primary,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
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
                IconButton(
                  onPressed: () => context.push('/lessons/$lessonId'),
                  icon: Icon(
                    Icons.edit_rounded,
                    size: 20,
                    color: cs.primary,
                  ),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(4),
                    minimumSize: const Size(32, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusFull,
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

class _RightColumn extends ConsumerWidget {
  const _RightColumn({required this.cs, required this.theme});
  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessonCountAsync = ref.watch(lessonCountProvider);
    final examCountAsync = ref.watch(examCountProvider);

    final lessonCount = lessonCountAsync.asData?.value ?? 0;
    final examCount = examCountAsync.asData?.value ?? 0;

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
                'Weekly Overview',
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
                          lessonCountAsync.isLoading ? '...' : '$lessonCount',
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
                        examCountAsync.isLoading ? '...' : '$examCount',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: cs.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
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

/// Provider that fetches the most recent lessons for the phone dashboard.
final recentLessonsProvider = FutureProvider<List<Lesson>>((ref) async {
  final db = ref.read(databaseProvider);
  return db.lessonsDao.getRecentLessons(limit: 5);
});

/// Provider that fetches the total count of lessons.
final lessonCountProvider = FutureProvider<int>((ref) async {
  final db = ref.read(databaseProvider);
  final lessons = await db.lessonsDao.getAll();
  return lessons.length;
});

/// Provider that fetches the total count of exams.
final examCountProvider = FutureProvider<int>((ref) async {
  final db = ref.read(databaseProvider);
  final exams = await db.examsDao.getAll();
  return exams.length;
});

final todayLessonCountProvider = FutureProvider<int>((ref) async {
  final db = ref.read(databaseProvider);
  final lessons = await db.lessonsDao.getAll();
  final today = DateTime.now();
  return lessons
      .where((lesson) =>
          lesson.createdAt.year == today.year &&
          lesson.createdAt.month == today.month &&
          lesson.createdAt.day == today.day)
      .length;
});

final lastUpdatedLessonProvider = FutureProvider<Lesson?>((ref) async {
  final db = ref.read(databaseProvider);
  final authData = ref.read(authProvider);
  final teacherId = authData.currentTeacher?.serverId;
  final lessons = await db.lessonsDao.getAll();
  final filtered = teacherId == null
      ? lessons
      : lessons.where((lesson) => lesson.teacherServerId == teacherId).toList();
  if (filtered.isEmpty) return null;
  filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return filtered.first;
});

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

  if (teacherId == null || teacherServerId == null) {
    return null;
  }

  final lessons = await db.lessonsDao.getAll();
  final teacherLessons = lessons
      .where((lesson) => lesson.teacherServerId == teacherServerId)
      .toList();
  if (teacherLessons.isEmpty) return null;

  final activeWeek = teacherLessons
      .map((lesson) => lesson.weekNumber ?? lesson.week)
      .reduce((a, b) => a > b ? a : b);

  final schemes = await db.schemeOfWorkDao.getApproved();
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncStatusProvider.notifier).refresh();
      ref.read(creditStateProvider.notifier).refresh();
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
    CreditStateData creditData,
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
              _CreditInfoRow(
                label: 'Available Credits',
                value:
                    creditData.loading ? '…' : '${creditData.currentCredits}',
                cs: cs,
                theme: theme,
              ),
              const SizedBox(height: 12),
              _CreditInfoRow(
                label: 'Tier',
                value: creditData.tierName,
                cs: cs,
                theme: theme,
              ),
              if (creditData.nextRefillTime != null) ...[
                const SizedBox(height: 12),
                _CreditInfoRow(
                  label: 'Next Refill',
                  value: DateFormat('MMM d, yyyy')
                      .format(creditData.nextRefillTime!),
                  cs: cs,
                  theme: theme,
                ),
              ],
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
    final creditData = ref.watch(creditStateProvider);

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
                const SizedBox(width: 12),
                Text(
                  'ClassAI',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
                const Spacer(),
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
                // Credit chip (live from creditStateProvider)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _showReaderCreditInfo(
                      context,
                      ref,
                      creditData,
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
                        creditData.loading
                            ? '…'
                            : '${creditData.currentCredits}',
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
          // ── Free Plan Banner ──────────────────────────────
          if (authData.currentSchool?.subscriptionTier == 'free')
            _FreePlanBanner(
              cs: cs,
              theme: theme,
              onUpgrade: () => context.push('/payment'),
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
                  const _CurrentWeekProgressCard(),
                  const SizedBox(height: 24),
                  const _TodayAtAGlanceStrip(),
                  const SizedBox(height: 24),
                  // Recent lesson cards (live from lessons database)
                  _RecentLessonsList(cs: cs, theme: theme),
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
        onTap: (index) {
          setState(() => _selectedIndex = index);
          _onNavDestination(context, index);
        },
      ),
    );
  }

  void _onNavDestination(BuildContext context, int index) {
    switch (index) {
      case 0:
        break; // Home (already here)
      case 1:
        _goToLessonsDeferred(context);
        break;
      case 2:
        context.push('/exams');
        break;
      case 3:
        context.push('/scheme-of-work');
        break;
      case 4:
        context.push('/settings');
        break;
    }
  }
}

/// Renders a list of recent lesson cards from the lessons database.
class _RecentLessonsList extends ConsumerWidget {
  const _RecentLessonsList({required this.cs, required this.theme});

  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessonsAsync = ref.watch(recentLessonsProvider);

    return lessonsAsync.when(
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

        return Column(
          children: [
            for (int i = 0; i < lessons.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              _ReaderLessonCard(
                lessonId: lessons[i].id,
                classLabel: lessons[i].classLevel,
                title: lessons[i].topic.isNotEmpty
                    ? lessons[i].topic
                    : lessons[i].subject,
                icon: Icons.menu_book_rounded,
                description: lessons[i].content.isNotEmpty
                    ? lessons[i].content.substring(
                        0, lessons[i].content.length > 120
                            ? 120
                            : lessons[i].content.length)
                    : 'No description available.',
                duration: '',
                buttonText: 'View Lesson',
                cs: cs,
                theme: theme,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TodayAtAGlanceStrip extends ConsumerWidget {
  const _TodayAtAGlanceStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final todayLessonsAsync = ref.watch(todayLessonCountProvider);
    final lessonCountAsync = ref.watch(lessonCountProvider);
    final examCountAsync = ref.watch(examCountProvider);
    final creditData = ref.watch(creditStateProvider);
    final syncData = ref.watch(syncStatusProvider);
    final conflictCount = ref.watch(unresolvedConflictsProvider);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _GlanceChip(
          label: 'Lessons',
          value: (todayLessonsAsync.asData?.value ?? 0) > 0
              ? '${todayLessonsAsync.asData?.value ?? 0} today'
              : lessonCountAsync.asData?.value != null
                  ? '${lessonCountAsync.asData?.value} total'
                  : '...',
          icon: Icons.menu_book_rounded,
          cs: cs,
          theme: theme,
        ),
        _GlanceChip(
          label: 'Exams',
          value: examCountAsync.asData?.value != null
              ? '${examCountAsync.asData?.value}'
              : '...',
          icon: Icons.quiz_rounded,
          cs: cs,
          theme: theme,
        ),
        _GlanceChip(
          label: 'Credits',
          value: creditData.loading ? '...' : '${creditData.currentCredits}',
          icon: Icons.toll_rounded,
          cs: cs,
          theme: theme,
        ),
        _GlanceChip(
          label: 'Sync',
          value: statusLabel(syncData.status),
          icon: syncData.status == SyncStatus.synced
              ? Icons.cloud_done_rounded
              : syncData.status == SyncStatus.syncing
                  ? Icons.sync_rounded
                  : syncData.status == SyncStatus.error
                      ? Icons.cloud_off_rounded
                      : Icons.cloud_queue_rounded,
          cs: cs,
          theme: theme,
        ),
        _GlanceChip(
          label: 'Conflicts',
          value: '$conflictCount',
          icon: Icons.warning_amber_rounded,
          cs: cs,
          theme: theme,
        ),
        _ResumeLessonCard(cs: cs, theme: theme),
      ],
    );
  }
}

class _GlanceChip extends StatelessWidget {
  const _GlanceChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.cs,
    required this.theme,
  });

  final String label;
  final String value;
  final IconData icon;
  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              Text(value, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResumeLessonCard extends ConsumerWidget {
  const _ResumeLessonCard({required this.cs, required this.theme});

  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessonAsync = ref.watch(lastUpdatedLessonProvider);
    final lesson = lessonAsync.asData?.value;
    if (lesson == null) return const SizedBox.shrink();

    return InkWell(
      onTap: () => _goToLessonEditorDeferred(context, lesson.id),
      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resume last lesson', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: cs.primary)),
            const SizedBox(height: 4),
            Text(
              lesson.topic.isNotEmpty ? lesson.topic : lesson.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('${lesson.classLevel} • ${lesson.subject}', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _ReaderLessonCard extends StatelessWidget {
  const _ReaderLessonCard({
    required this.lessonId,
    required this.classLabel,
    required this.title,
    required this.icon,
    required this.description,
    required this.duration,
    required this.buttonText,
    required this.cs,
    required this.theme,
  });

  final int lessonId;
  final String classLabel;
  final String title;
  final IconData icon;
  final String description;
  final String duration;
  final String buttonText;
  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.secondaryFixed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusDefault,
                      ),
                    ),
                    child: Text(
                      classLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.secondaryFixedDim,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(
                    AppTheme.radiusFull,
                  ),
                ),
                child: Icon(icon, size: 20, color: cs.outline),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: cs.outline,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      duration,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.outline,
                        overflow: TextOverflow.clip,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: AppTheme.touchTarget,
                child: FilledButton(
                  onPressed: () => context.push('/lessons/$lessonId'),
                  child: Text(
                    buttonText,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w500,
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
}

class _ReaderBottomNav extends StatelessWidget {
  const _ReaderBottomNav({
    required this.selectedIndex,
    required this.cs,
    required this.theme,
    required this.onTap,
  });

  final int selectedIndex;
  final ColorScheme cs;
  final ThemeData theme;
  final ValueChanged<int> onTap;

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
          Expanded(child: _BottomNavItem(
            icon: Icons.home_rounded,
            label: 'Home',
            isActive: selectedIndex == 0,
            isFilled: false,
            cs: cs,
            theme: theme,
            onTap: () => onTap(0),
          )),
          Expanded(child: _BottomNavItem(
            icon: Icons.menu_book_rounded,
            label: 'Lessons',
            isActive: selectedIndex == 1,
            isFilled: true,
            cs: cs,
            theme: theme,
            onTap: () => onTap(1),
          )),
          Expanded(child: _BottomNavItem(
            icon: Icons.quiz_rounded,
            label: 'Exams',
            isActive: selectedIndex == 2,
            isFilled: false,
            cs: cs,
            theme: theme,
            onTap: () => onTap(2),
          )),
          Expanded(child: _BottomNavItem(
            icon: Icons.calendar_month_rounded,
            label: 'Scheme of Work',
            isActive: selectedIndex == 3,
            isFilled: false,
            cs: cs,
            theme: theme,
            onTap: () => onTap(3),
          )),
          Expanded(child: _BottomNavItem(
            icon: Icons.more_horiz_rounded,
            label: 'More',
            isActive: selectedIndex == 4,
            isFilled: false,
            cs: cs,
            theme: theme,
            onTap: () => onTap(4),
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
        color: Colors.amber.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.amber.shade200),
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
                fontWeight: FontWeight.w500,
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
