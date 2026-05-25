import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/core/utils/platform_helper.dart';
import 'package:classai/core/theme/app_theme.dart';
import 'package:classai/core/widgets/conflict_banner.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/sync_status_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/features/dashboard/providers/unresolved_conflicts_provider.dart';
import 'package:classai/features/settings/providers/theme_provider.dart';

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
    });
  }

  @override
  Widget build(BuildContext context) {
    // Platform gate: non-mobile platforms always use the editor layout
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const EditorLayout();
    }

    if (_isEditorMode == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return _isEditorMode! ? const EditorLayout() : const ReaderLayout();
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

  List<_NavItem> get _navItems {
    final authData = ref.read(authProvider);
    final isAdmin = authData.currentTeacher?.role == 'admin';
    return [
      _NavItem(icon: Icons.home_rounded, label: 'Home', route: null),
      _NavItem(icon: Icons.menu_book_rounded, label: 'Lessons', route: '/lessons'),
      _NavItem(icon: Icons.quiz_rounded, label: 'Exams', route: '/exams'),
      _NavItem(icon: Icons.inventory_2_rounded, label: 'Vault', route: '/vault'),
      if (isAdmin)
        _NavItem(icon: Icons.admin_panel_settings_rounded, label: 'Admin', route: '/admin'),
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
          Container(
            width: 288,
            color: cs.surfaceContainerLow,
            child: Column(
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ClassAI',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: cs.primary,
                            ),
                          ),
                          Text(
                            'Nigerian Academic Partner',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
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
                            context.push(item.route!);
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
                      Text(
                        'Dashboard',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                      const Spacer(),
                      // Sync indicator (Stitch green dot style)
                      _SyncChip(cs: cs),
                      const SizedBox(width: 16),
                      // Credit chip
                      _CreditChip(cs: cs, theme: theme),
                      const SizedBox(width: 12),
                      // Profile popup
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          switch (value) {
                            case 'settings':
                              context.push('/settings');
                            case 'logout':
                              ref.read(authProvider.notifier).manualLogout();
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

                // ── Canvas ─────────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
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
                                        'Good Morning, Educator',
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
                                Row(
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
                                    const SizedBox(width: 12),
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

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.label,
    this.route,
  });
  final IconData icon;
  final String label;
  final String? route;
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF008751).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF008751),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Synced',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF008751),
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

class _CreditChip extends StatelessWidget {
  const _CreditChip({required this.cs, required this.theme});
  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_balance_wallet_rounded,
            size: 20,
            color: cs.primary,
          ),
          const SizedBox(width: 8),
          Text(
            '₦1,250',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
          ),
        ],
      ),
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

class _RecentLessonsSection extends StatelessWidget {
  const _RecentLessonsSection({required this.cs, required this.theme});
  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Lessons',
              style: theme.textTheme.titleLarge?.copyWith(
                color: cs.primary,
              ),
            ),
            TextButton(
              onPressed: () => context.push('/lessons'),
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
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 600;
            if (twoColumns) {
              return Row(
                children: [
                  Expanded(
                    child: _LessonCard(
                      icon: Icons.science_rounded,
                      iconColor: cs.tertiaryContainer,
                      title: 'Introduction to Photosynthesis',
                      subtitle: 'JSS 2 • Biology',
                      status: 'Draft',
                      statusColor: cs.onSurfaceVariant,
                      statusBg: cs.surfaceContainerHighest,
                      timeAgo: 'Last edited 2h ago',
                      cs: cs,
                      theme: theme,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _LessonCard(
                      icon: Icons.calculate_rounded,
                      iconColor: cs.onSecondaryContainer,
                      iconBg: cs.secondaryContainer.withValues(alpha: 0.2),
                      title: 'Algebraic Expressions',
                      subtitle: 'SS 1 • Mathematics',
                      status: 'Published',
                      statusColor: const Color(0xFF008751),
                      statusBg: const Color(0xFF008751).withValues(alpha: 0.1),
                      timeAgo: 'Last edited yesterday',
                      cs: cs,
                      theme: theme,
                    ),
                  ),
                ],
              );
            } else {
              return Column(
                children: [
                  _LessonCard(
                    icon: Icons.science_rounded,
                    iconColor: cs.tertiaryContainer,
                    title: 'Introduction to Photosynthesis',
                    subtitle: 'JSS 2 • Biology',
                    status: 'Draft',
                    statusColor: cs.onSurfaceVariant,
                    statusBg: cs.surfaceContainerHighest,
                    timeAgo: 'Last edited 2h ago',
                    cs: cs,
                    theme: theme,
                  ),
                  const SizedBox(height: 16),
                  _LessonCard(
                    icon: Icons.calculate_rounded,
                    iconColor: cs.onSecondaryContainer,
                    iconBg: cs.secondaryContainer.withValues(alpha: 0.2),
                    title: 'Algebraic Expressions',
                    subtitle: 'SS 1 • Mathematics',
                    status: 'Published',
                    statusColor: const Color(0xFF008751),
                    statusBg: const Color(0xFF008751).withValues(alpha: 0.1),
                    timeAgo: 'Last edited yesterday',
                    cs: cs,
                    theme: theme,
                  ),
                ],
              );
            }
          },
        ),
      ],
    );
  }
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({
    required this.icon,
    required this.iconColor,
    this.iconBg,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.statusColor,
    required this.statusBg,
    required this.timeAgo,
    required this.cs,
    required this.theme,
  });

  final IconData icon;
  final Color iconColor;
  final Color? iconBg;
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
                  color: iconBg ?? iconColor.withValues(alpha: 0.1),
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
                Text(
                  timeAgo,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                IconButton(
                  onPressed: () {},
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

class _RightColumn extends StatelessWidget {
  const _RightColumn({required this.cs, required this.theme});
  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
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
                          '12',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: cs.onPrimary,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.trending_up_rounded,
                          size: 16,
                          color: cs.secondaryFixed,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '+2',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.secondaryFixed,
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
                        '4',
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

        const SizedBox(height: 24),

        // Upcoming Schedule
        Container(
          padding: const EdgeInsets.all(24),
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
              Text(
                'Upcoming Schedule',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 16),
              _ScheduleItem(
                time: '10:00 AM',
                title: 'JSS 2 Biology Class',
                subtitle: 'Room 4B • 45 Students',
                borderColor: cs.tertiaryContainer,
                cs: cs,
                theme: theme,
              ),
              const SizedBox(height: 12),
              _ScheduleItem(
                time: '11:30 AM',
                title: 'SS 1 Math Exam',
                subtitle: 'Main Hall • Invigilation',
                borderColor: cs.secondary,
                cs: cs,
                theme: theme,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScheduleItem extends StatelessWidget {
  const _ScheduleItem({
    required this.time,
    required this.title,
    required this.subtitle,
    required this.borderColor,
    required this.cs,
    required this.theme,
  });

  final String time;
  final String title;
  final String subtitle;
  final Color borderColor;
  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          child: Column(
            children: [
              Text(
                time.split(' ').first,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.outline,
                ),
              ),
              Text(
                time.split(' ').last,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.outline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              border: Border(
                left: BorderSide(color: borderColor, width: 4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  READER LAYOUT (Phone)
//  Matches stitch_design_v2/dashboard_reader_phone/code.html
// ═══════════════════════════════════════════════════════════════════════════

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final authData = ref.watch(authProvider);
    final themeMode = ref.watch(themeProvider);

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
                        ref.read(authProvider.notifier).manualLogout();
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
                // Offline indicator
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Color(0xFF9E9E9E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Offline',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                // Credit chip
                Container(
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
                    '₦1,250',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
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
            // Lesson cards
            _ReaderLessonCard(
              classLabel: 'SS1',
              title: 'Mathematics',
              icon: Icons.calculate_rounded,
              description:
                  'Algebraic expressions, factoring polynomials, and solving quadratic equations. Review the examples from yesterday\'s session before starting the practice set.',
              duration: '45 mins',
              buttonText: 'Resume Reading',
              cs: cs,
              theme: theme,
            ),
            const SizedBox(height: 16),
            _ReaderLessonCard(
              classLabel: 'JSS3',
              title: 'English Language',
              icon: Icons.menu_book_rounded,
              description:
                  'Comprehension passages: "The Market Square". Focus on identifying the main idea and supporting details in paragraphs 2 and 3.',
              duration: '30 mins',
              buttonText: 'Start Lesson',
              cs: cs,
              theme: theme,
            ),
          ],
        ),
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
        context.push('/lessons');
        break;
      case 2:
        context.push('/exams');
        break;
      case 3:
        context.push('/settings');
        break;
    }
  }
}

class _ReaderLessonCard extends StatelessWidget {
  const _ReaderLessonCard({
    required this.classLabel,
    required this.title,
    required this.icon,
    required this.description,
    required this.duration,
    required this.buttonText,
    required this.cs,
    required this.theme,
  });

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
        color: const Color(0xFFF5F7F9),
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
                  Text(
                    duration,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.outline,
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: AppTheme.touchTarget,
                child: FilledButton(
                  onPressed: () {},
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
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _BottomNavItem(
            icon: Icons.home_rounded,
            label: 'Home',
            isActive: selectedIndex == 0,
            isFilled: false,
            cs: cs,
            theme: theme,
            onTap: () => onTap(0),
          ),
          _BottomNavItem(
            icon: Icons.menu_book_rounded,
            label: 'Lessons',
            isActive: selectedIndex == 1,
            isFilled: true,
            cs: cs,
            theme: theme,
            onTap: () => onTap(1),
          ),
          _BottomNavItem(
            icon: Icons.quiz_rounded,
            label: 'Exams',
            isActive: selectedIndex == 2,
            isFilled: false,
            cs: cs,
            theme: theme,
            onTap: () => onTap(2),
          ),
          _BottomNavItem(
            icon: Icons.more_horiz_rounded,
            label: 'More',
            isActive: selectedIndex == 3,
            isFilled: false,
            cs: cs,
            theme: theme,
            onTap: () => onTap(3),
          ),
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
      onTap: onTap,
      child: Container(
        width: 64,
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
