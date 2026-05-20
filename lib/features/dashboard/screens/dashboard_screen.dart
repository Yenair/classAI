import 'dart:io' show Platform;
import 'dart:ui'; // BackdropFilter
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/core/utils/platform_helper.dart';
import 'package:classai/core/widgets/sync_indicator.dart';
import 'package:classai/core/widgets/credit_counter.dart';
import 'package:classai/core/widgets/conflict_banner.dart';
import 'package:classai/features/dashboard/providers/sync_status_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/features/dashboard/providers/unresolved_conflicts_provider.dart';

/// Root dashboard screen that routes to either [EditorLayout] or [ReaderLayout]
/// based on [PlatformHelper.isEditorMode].
///
/// Platform gate: On non-mobile platforms (desktop/web), always uses
/// [EditorLayout] since those platforms have large screens that benefit
/// from the wider layout. The mobile layout decision (width-based
/// EditorLayout/ReaderLayout switch) is only used on Android and iOS.
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
    // Defer the async platform-mode check to after the first frame so it
    // never runs during the widget build phase (which could trigger a
    // navigator transition while the navigator is still locked from a
    // previous push/pop animation).
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

    // Still loading editor mode — show a simple loading indicator.
    // This runs synchronously during build and never creates an async
    // Future in the build method, so it cannot trigger a navigation
    // call while the navigator is locked.
    if (_isEditorMode == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return _isEditorMode! ? const EditorLayout() : const ReaderLayout();
  }
}

// ---------------------------------------------------------------------------
// Editor Layout (desktop / large tablet)
// ---------------------------------------------------------------------------

class EditorLayout extends ConsumerStatefulWidget {
  const EditorLayout({super.key});

  @override
  ConsumerState<EditorLayout> createState() => _EditorLayoutState();
}

class _EditorLayoutState extends ConsumerState<EditorLayout> {
  int _selectedIndex = 0;

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.school_rounded),
      selectedIcon: Icon(Icons.school_rounded),
      label: 'Dashboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.menu_book_rounded),
      selectedIcon: Icon(Icons.menu_book_rounded),
      label: 'Lessons',
    ),
    NavigationDestination(
      icon: Icon(Icons.description_rounded),
      selectedIcon: Icon(Icons.description_rounded),
      label: 'Exams',
    ),
    NavigationDestination(
      icon: Icon(Icons.folder_outlined),
      selectedIcon: Icon(Icons.folder),
      label: 'Vault',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_rounded),
      selectedIcon: Icon(Icons.settings_rounded),
      label: 'More',
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Kick off async data loading
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncStatusProvider.notifier).refresh();
      ref.read(creditStateProvider.notifier).refresh();
      ref.read(unresolvedConflictsProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'ClassAI',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.12,
                color: cs.onSurface,
              ),
        ),
        actions: const [
          CreditCounter(),
          SizedBox(width: 4),
          SyncIndicator(),
          SizedBox(width: 8),
        ],
        elevation: 0,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: cs.surface,
      ),
      body: Column(
        children: [
          const ConflictBanner(),
          Expanded(
            child: Row(
              children: [
                // ── Navigation Rail ──────────────────────────────
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow.withAlpha(128),
                        border: const Border(
                          right: BorderSide(
                            color: Color(0xFFC1C7D2),
                            width: 1,
                          ),
                        ),
                      ),
                      child: NavigationRail(
                        selectedIndex: _selectedIndex,
                        onDestinationSelected: (index) {
                          setState(() => _selectedIndex = index);
                          _onNavDestination(context, index);
                        },
                        extended: true,
                        minExtendedWidth: 200,
                        backgroundColor: Colors.transparent,
                        indicatorColor: cs.secondaryContainer,
                        destinations: _destinations
                            .map((d) => NavigationRailDestination(
                                  icon: d.icon,
                                  selectedIcon: d.selectedIcon,
                                  label: Text(
                                    d.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                ),
                // ── Content ───────────────────────────────────────
                const Expanded(
                  child: _EditorContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onNavDestination(BuildContext context, int index) {
    switch (index) {
      case 1:
        context.push('/lessons');
        break;
      case 2:
        context.push('/exams');
        break;
      case 3:
        context.push('/vault');
        break;
      case 4:
        context.push('/settings');
        break;
    }
  }
}

/// Central dashboard content shown in the EditorLayout pane.
class _EditorContent extends ConsumerWidget {
  const _EditorContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Container(
      color: cs.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Page title ────────────────────────────────────
                Text(
                  'Welcome to ClassAI',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nigerian Academic Partner — your intelligent teaching assistant.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 32),

                // ── Quick-action cards ───────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _QuickActionCard(
                        icon: Icons.school_rounded,
                        label: 'New Lesson',
                        cs: cs,
                        onTap: () => context.push('/lesson-editor'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _QuickActionCard(
                        icon: Icons.assignment_rounded,
                        label: 'New Exam',
                        cs: cs,
                        onTap: () => context.push('/exam-editor'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _QuickActionCard(
                        icon: Icons.folder_rounded,
                        label: 'Vault',
                        cs: cs,
                        onTap: () => context.push('/vault'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.cs,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final ColorScheme cs;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.onSurface.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, size: 24, color: cs.primary),
                ),
                const SizedBox(height: 14),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
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

// ---------------------------------------------------------------------------
// Reader Layout (phone / small tablet)
// ---------------------------------------------------------------------------

class ReaderLayout extends ConsumerStatefulWidget {
  const ReaderLayout({super.key});

  @override
  ConsumerState<ReaderLayout> createState() => _ReaderLayoutState();
}

class _ReaderLayoutState extends ConsumerState<ReaderLayout> {
  int _selectedIndex = 0;

  static const _destinations = <BottomNavigationBarItem>[
    BottomNavigationBarItem(
      icon: Icon(Icons.school_rounded),
      activeIcon: Icon(Icons.school_rounded),
      label: 'Home',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.menu_book_rounded),
      activeIcon: Icon(Icons.menu_book_rounded),
      label: 'Lessons',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.description_rounded),
      activeIcon: Icon(Icons.description_rounded),
      label: 'Exams',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.settings_rounded),
      activeIcon: Icon(Icons.settings_rounded),
      label: 'More',
    ),
  ];

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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'ClassAI',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.12,
            color: cs.onSurface,
          ),
        ),
        actions: const [
          CreditCounter(),
          SizedBox(width: 4),
          SyncIndicator(),
          SizedBox(width: 8),
        ],
        elevation: 0,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: cs.surface,
      ),
      body: Column(
        children: [
          const ConflictBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Icon(
                          Icons.school_rounded,
                          size: 36,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Welcome to ClassAI',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Nigerian Academic Partner — your intelligent teaching assistant.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ── Quick action buttons ────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: _ReaderActionButton(
                              icon: Icons.auto_stories_rounded,
                              label: 'Lessons',
                              onTap: () => context.push('/lessons'),
                              cs: cs,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ReaderActionButton(
                              icon: Icons.assignment_rounded,
                              label: 'Exams',
                              onTap: () => context.push('/exams'),
                              cs: cs,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: cs.surfaceContainerLowest,
          selectedItemColor: cs.primary,
          unselectedItemColor: cs.onSurfaceVariant,
          selectedFontSize: 12,
          unselectedFontSize: 11,
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() => _selectedIndex = index);
            _onNavDestination(context, index);
          },
          items: _destinations,
          selectedLabelStyle: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(inherit: true, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  void _onNavDestination(BuildContext context, int index) {
    switch (index) {
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

class _ReaderActionButton extends StatelessWidget {
  const _ReaderActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.cs,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: cs.primary),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
