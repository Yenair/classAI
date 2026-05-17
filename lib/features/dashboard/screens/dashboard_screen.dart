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
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<bool>(
      future: PlatformHelper.isEditorMode(context),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snap.data!
            ? const EditorLayout()
            : const ReaderLayout();
      },
    );
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
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: 'Dashboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.book_outlined),
      selectedIcon: Icon(Icons.book),
      label: 'Lessons',
    ),
    NavigationDestination(
      icon: Icon(Icons.quiz_outlined),
      selectedIcon: Icon(Icons.quiz),
      label: 'Exams',
    ),
    NavigationDestination(
      icon: Icon(Icons.folder_outlined),
      selectedIcon: Icon(Icons.folder),
      label: 'Vault',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
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
    final isCompact = MediaQuery.of(context).size.width <= 1024;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ClassAI'),
        actions: [
          const CreditCounter(),
          const SizedBox(width: 4),
          const SyncIndicator(),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          const ConflictBanner(),
          Expanded(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    setState(() => _selectedIndex = index);
                    _onNavDestination(context, index);
                  },
                  labelType: isCompact
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.selected,
                  extended: !isCompact,
                  minExtendedWidth: 200,
                  destinations: _destinations
                      .map((d) => NavigationRailDestination(
                            icon: d.icon,
                            selectedIcon: d.selectedIcon,
                            label: Text(d.label),
                          ))
                      .toList(),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _buildContent(theme),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          'Welcome to ClassAI',
          style: theme.textTheme.headlineSmall,
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
        context.push('/vault');
        break;
      case 4:
        context.push('/settings');
        break;
    }
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
      icon: Icon(Icons.home_outlined),
      activeIcon: Icon(Icons.home),
      label: 'Home',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.book_outlined),
      activeIcon: Icon(Icons.book),
      label: 'Lessons',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.quiz_outlined),
      activeIcon: Icon(Icons.quiz),
      label: 'Exams',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.more_horiz_outlined),
      activeIcon: Icon(Icons.more_horiz),
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ClassAI'),
        actions: [
          const CreditCounter(),
          const SizedBox(width: 4),
          const SyncIndicator(),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          const ConflictBanner(),
          Expanded(
            child: _buildContent(theme),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 16,
        unselectedFontSize: 14,
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
          _onNavDestination(context, index);
        },
        items: _destinations,
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          'Welcome to ClassAI',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: 18, // ≥16pt for reader mode
          ),
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
