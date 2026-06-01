// lib/features/vault/screens/vault_browser_screen.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/main.dart' show databaseProvider;
import 'package:classai/core/theme/app_theme.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/features/vault/screens/vault_item_detail_screen.dart';

/// Vault browser screen showing approved items in a searchable grid.
///
/// Teachers can browse, filter, and acquire vault items using credits.
class VaultBrowserScreen extends ConsumerStatefulWidget {
  const VaultBrowserScreen({super.key});

  @override
  ConsumerState<VaultBrowserScreen> createState() =>
      _VaultBrowserScreenState();
}

class _VaultBrowserScreenState extends ConsumerState<VaultBrowserScreen> {
  List<VaultItem> _items = [];
  bool _loading = true;
  String? _errorMessage;

  // Filter state
  String? _filterSubject;
  String? _filterClassLevel;
  String? _filterCurriculum;

  // Search query
  String _searchQuery = '';

  // Dynamic filter options (populated from loaded items)
  List<String> _subjectOptions = [];
  List<String> _classLevelOptions = [];
  List<String> _curriculumOptions = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      final dao = ref.read(databaseProvider).vaultItemsDao;
      final items = await dao.filter(
        subject: _filterSubject,
        classLevel: _filterClassLevel,
        curriculum: _filterCurriculum,
      );
      // Derive distinct filter options from all approved items
      final allItems = await dao.getApprovedItems();
      final subjects = allItems.map((e) => e.subject).toSet().toList()..sort();
      final classLevels = allItems.map((e) => e.classLevel).toSet().toList()..sort();
      final curriculums = allItems.map((e) => e.curriculum).toSet().toList()..sort();
      setState(() {
        _items = items;
        _errorMessage = null;
        _subjectOptions = subjects;
        _classLevelOptions = classLevels;
        _curriculumOptions = curriculums;
      });
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load vault items: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _openDetail(VaultItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VaultItemDetailScreen(item: item),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 768;
    final authData = ref.watch(authProvider);
    final teacherName = authData.currentTeacher?.teacherName ?? 'Educator Profile';
    final teacherInitials = _getInitials(teacherName);

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Row(
          children: [
            // -------------------------------------------------------
            // Navigation Drawer (Tablet/Desktop)
            // -------------------------------------------------------
            if (isDesktop)
              _NavDrawer(cs: cs, tt: tt, teacherName: teacherName, teacherInitials: teacherInitials),

            // -------------------------------------------------------
            // Main Content Area
            // -------------------------------------------------------
            Expanded(
              child: Column(
                children: [
                  // TopAppBar (Mobile only)
                  if (!isDesktop)
                    _MobileHeader(cs: cs, tt: tt, ref: ref, teacherName: teacherName, teacherInitials: teacherInitials),

                  // Scrollable main canvas
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _errorMessage != null
                            ? _ErrorState(
                                cs: cs,
                                tt: tt,
                                errorMessage: _errorMessage!,
                                onRetry: _loadItems,
                              )
                            : _items.isEmpty
                                ? _EmptyState(cs: cs, tt: tt)
                                : _VaultContent(
                                    cs: cs,
                                    tt: tt,
                                    items: _items,
                                    searchQuery: _searchQuery,
                                    filterSubject: _filterSubject,
                                    filterClassLevel: _filterClassLevel,
                                    filterCurriculum: _filterCurriculum,
                                    onSearchChanged: (q) =>
                                        setState(() => _searchQuery = q),
                                    onFilterSubjectChanged: (v) => setState(
                                        () => _filterSubject = v),
                                    onFilterClassLevelChanged: (v) =>
                                        setState(
                                            () => _filterClassLevel = v),
                                    onFilterCurriculumChanged: (v) =>
                                        setState(
                                            () => _filterCurriculum = v),
                                    onApplyFilters: _loadItems,
                                    subjectOptions: _subjectOptions,
                                    classLevelOptions: _classLevelOptions,
                                    curriculumOptions: _curriculumOptions,
                                    onOpenDetail: _openDetail,
                                    getInitials: _getInitials,
                                  ),
                  ),

                  // BottomNavBar (Mobile only)
                  if (!isDesktop)
                    _BottomNav(cs: cs, tt: tt),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation Drawer (Tablet/Desktop)
// ---------------------------------------------------------------------------
class _NavDrawer extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme tt;
  final String teacherName;
  final String teacherInitials;

  const _NavDrawer({
    required this.cs,
    required this.tt,
    required this.teacherName,
    required this.teacherInitials,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 288,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Branding
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ClassAI',
                  style: tt.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Nigerian Academic Partner',
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // Nav items
          Expanded(
            child: Column(
              children: [
                _navItem(
                  cs: cs,
                  tt: tt,
                  icon: Icons.home_outlined,
                  label: 'Home',
                  isActive: false,
                  onTap: () => context.go('/'),
                ),
                _navItem(
                  cs: cs,
                  tt: tt,
                  icon: Icons.menu_book_rounded,
                  label: 'Lessons',
                  isActive: false,
                  onTap: () => context.go('/lessons'),
                ),
                _navItem(
                  cs: cs,
                  tt: tt,
                  icon: Icons.quiz_outlined,
                  label: 'Exams',
                  isActive: false,
                  onTap: () => context.go('/exams'),
                ),
                _navItem(
                  cs: cs,
                  tt: tt,
                  icon: Icons.inventory_2_rounded,
                  label: 'Vault',
                  isActive: true,
                  onTap: () {},
                ),
                _navItem(
                  cs: cs,
                  tt: tt,
                  icon: Icons.admin_panel_settings_outlined,
                  label: 'Admin',
                  isActive: false,
                  onTap: () => context.go('/admin'),
                ),
              ],
            ),
          ),
          // Profile footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            margin: const EdgeInsets.only(top: 16),
            child: Column(
              children: [
                const Divider(height: 1),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusFull),
                      ),
                      child: Center(
                        child: Text(
                          teacherInitials,
                          style: tt.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimary,
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
                            teacherName,
                            style: tt.labelLarge?.copyWith(
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Synced',
                                style: tt.labelMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem({
    required ColorScheme cs,
    required TextTheme tt,
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        height: AppTheme.touchTarget,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isActive ? cs.secondaryFixed : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        transform: isActive ? Matrix4.translationValues(4.0, 0.0, 0.0) : null,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isActive
                      ? cs.onSecondaryFixed
                      : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: tt.labelLarge?.copyWith(
                    color: isActive
                        ? cs.onSecondaryFixed
                        : cs.onSurfaceVariant,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
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
// Mobile Header
// ---------------------------------------------------------------------------
class _MobileHeader extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme tt;
  final WidgetRef ref;
  final String teacherName;
  final String teacherInitials;

  const _MobileHeader({
    required this.cs,
    required this.tt,
    required this.ref,
    required this.teacherName,
    required this.teacherInitials,
  });

  @override
  Widget build(BuildContext context) {
    final credits = ref.watch(creditStateProvider).currentCredits;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMarginMobile),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // Avatar placeholder (hidden for layout symmetry)
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            ),
            child: Center(
              child: Text(
                teacherInitials,
                style: tt.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'ClassAI',
            style: tt.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // Credit chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '\u20A6$credits',
            style: tt.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error State
// ---------------------------------------------------------------------------
class _ErrorState extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme tt;
  final String errorMessage;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.cs,
    required this.tt,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
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
              errorMessage,
              textAlign: TextAlign.center,
              style: tt.bodyLarge?.copyWith(color: cs.error),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty State
// ---------------------------------------------------------------------------
class _EmptyState extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme tt;

  const _EmptyState({required this.cs, required this.tt});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 64,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No vault items found',
            style: tt.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Adjust filters or check back later.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vault Content (Header + Search + Filters + Grid)
// ---------------------------------------------------------------------------
class _VaultContent extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme tt;
  final List<VaultItem> items;
  final String searchQuery;
  final String? filterSubject;
  final String? filterClassLevel;
  final String? filterCurriculum;
  final List<String> subjectOptions;
  final List<String> classLevelOptions;
  final List<String> curriculumOptions;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onFilterSubjectChanged;
  final ValueChanged<String?> onFilterClassLevelChanged;
  final ValueChanged<String?> onFilterCurriculumChanged;
  final VoidCallback onApplyFilters;
  final void Function(VaultItem) onOpenDetail;
  final String Function(String) getInitials;

  const _VaultContent({
    required this.cs,
    required this.tt,
    required this.items,
    required this.searchQuery,
    required this.filterSubject,
    required this.filterClassLevel,
    required this.filterCurriculum,
    required this.subjectOptions,
    required this.classLevelOptions,
    required this.curriculumOptions,
    required this.onSearchChanged,
    required this.onFilterSubjectChanged,
    required this.onFilterClassLevelChanged,
    required this.onFilterCurriculumChanged,
    required this.onApplyFilters,
    required this.onOpenDetail,
    required this.getInitials,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 1200
            ? 4
            : constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 600
                    ? 2
                    : 1;

        return SingleChildScrollView(

          physics: (Platform.isAndroid || Platform.isIOS)
              ? const BouncingScrollPhysics()
              : null,
          padding: const EdgeInsets.only(
            left: AppTheme.spacingMarginMobile,
            right: AppTheme.spacingMarginMobile,
            top: AppTheme.spacingGutter,
            bottom: 90,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Page Header + Search
              _PageHeader(
                cs: cs,
                tt: tt,
                searchQuery: searchQuery,
                onSearchChanged: onSearchChanged,
              ),
              const SizedBox(height: 24),
              // Filter bar
              _FilterChipsRow(
                cs: cs,
                tt: tt,
                filterSubject: filterSubject,
                filterClassLevel: filterClassLevel,
                filterCurriculum: filterCurriculum,
                subjectOptions: subjectOptions,
                classLevelOptions: classLevelOptions,
                curriculumOptions: curriculumOptions,
                onFilterSubjectChanged: onFilterSubjectChanged,
                onFilterClassLevelChanged: onFilterClassLevelChanged,
                onFilterCurriculumChanged: onFilterCurriculumChanged,
                onApplyFilters: onApplyFilters,
              ),
              const SizedBox(height: 24),
              // Bento grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 24,
                  mainAxisSpacing: 24,
                  childAspectRatio: 0.72,
                  mainAxisExtent: null,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _VaultCard(
                    item: item,
                    cs: cs,
                    tt: tt,
                    getInitials: getInitials,
                    onTap: () => onOpenDetail(item),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Page Header + Search
// ---------------------------------------------------------------------------
class _PageHeader extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme tt;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  const _PageHeader({
    required this.cs,
    required this.tt,
    required this.searchQuery,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title row + search
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 600;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + description
                SizedBox(
                  width: isWide ? null : double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resource Vault',
                        style: tt.displayLarge?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Access premium Nigerian National Curriculum aligned teaching materials, lesson plans, and exam preparatory content.',
                        style: tt.bodyLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isWide) const SizedBox(height: 16),
                // Search bar
                SizedBox(
                  width: isWide ? 320 : double.infinity,
                  child: TextField(
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search resources...',
                      hintStyle: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                      filled: true,
                      fillColor: cs.surfaceContainerLow,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusFull),
                        borderSide: BorderSide(
                          color: cs.outlineVariant,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusFull),
                        borderSide: BorderSide(
                          color: cs.outlineVariant,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusFull),
                        borderSide: BorderSide(
                          color: cs.primary,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Filter Chips Row (horizontally scrollable)
// ---------------------------------------------------------------------------
class _FilterChipsRow extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme tt;
  final String? filterSubject;
  final String? filterClassLevel;
  final String? filterCurriculum;
  final List<String> subjectOptions;
  final List<String> classLevelOptions;
  final List<String> curriculumOptions;
  final ValueChanged<String?> onFilterSubjectChanged;
  final ValueChanged<String?> onFilterClassLevelChanged;
  final ValueChanged<String?> onFilterCurriculumChanged;
  final VoidCallback onApplyFilters;

  const _FilterChipsRow({
    required this.cs,
    required this.tt,
    required this.filterSubject,
    required this.filterClassLevel,
    required this.filterCurriculum,
    required this.subjectOptions,
    required this.classLevelOptions,
    required this.curriculumOptions,
    required this.onFilterSubjectChanged,
    required this.onFilterClassLevelChanged,
    required this.onFilterCurriculumChanged,
    required this.onApplyFilters,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(

      physics: (Platform.isAndroid || Platform.isIOS)
          ? const BouncingScrollPhysics()
          : null,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // All Filters pill
          Container(
            height: AppTheme.touchTarget,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            ),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 18, color: cs.onPrimary),
                const SizedBox(width: 8),
                Text(
                  'All Filters',
                  style: tt.labelLarge?.copyWith(color: cs.onPrimary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Subject dropdown
          _FilterDropdown(
            cs: cs,
            tt: tt,
            hint: 'Subject: All',
            value: filterSubject,
            options: subjectOptions,
            onChanged: (v) {
              onFilterSubjectChanged(v);
              onApplyFilters();
            },
          ),
          const SizedBox(width: 12),
          // Class dropdown
          _FilterDropdown(
            cs: cs,
            tt: tt,
            hint: 'Class: All',
            value: filterClassLevel,
            options: classLevelOptions,
            onChanged: (v) {
              onFilterClassLevelChanged(v);
              onApplyFilters();
            },
          ),
          const SizedBox(width: 12),
          // Curriculum dropdown
          _FilterDropdown(
            cs: cs,
            tt: tt,
            hint: 'Curriculum: All',
            value: filterCurriculum,
            options: curriculumOptions,
            onChanged: (v) {
              onFilterCurriculumChanged(v);
              onApplyFilters();
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter Dropdown (rounded-full style)
// ---------------------------------------------------------------------------
class _FilterDropdown extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme tt;
  final String hint;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({
    required this.cs,
    required this.tt,
    required this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppTheme.touchTarget,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(
            hint,
            style: tt.labelLarge?.copyWith(color: cs.onSurface),
          ),
          isDense: true,
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Text(
                hint,
                style: tt.labelLarge?.copyWith(color: cs.onSurface),
              ),
            ),
            ...options.map(
              (opt) => DropdownMenuItem<String>(
                value: opt,
                child: Text(
                  opt,
                  style: tt.labelLarge?.copyWith(color: cs.onSurface),
                ),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vault Item Card
// ---------------------------------------------------------------------------
class _VaultCard extends StatelessWidget {
  final VaultItem item;
  final ColorScheme cs;
  final TextTheme tt;
  final String Function(String) getInitials;
  final VoidCallback onTap;

  const _VaultCard({
    required this.item,
    required this.cs,
    required this.tt,
    required this.getInitials,
    required this.onTap,
  });

  bool get _isPremium =>
      item.minTier.toLowerCase() != 'free';

  bool get _isFree =>
      item.minTier.toLowerCase() == 'free';

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image header (h-48 = 200px)
              Stack(
                children: [
                  Container(
                    height: 160,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(AppTheme.radiusXl),
                        topRight: Radius.circular(AppTheme.radiusXl),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: item.thumbnailUrl != null &&
                            item.thumbnailUrl!.isNotEmpty
                        ? Image.network(
                            item.thumbnailUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _ThumbnailPlaceholder(
                              cs: cs,
                              tt: tt,
                              item: item,
                            ),
                          )
                        : _ThumbnailPlaceholder(
                            cs: cs,
                            tt: tt,
                            item: item,
                          ),
                  ),
                  // Tier badge
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _isPremium
                            ? cs.secondaryContainer
                            : cs.surface,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusLg),
                        boxShadow: _isFree
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isPremium)
                            Icon(
                              Icons.workspace_premium_rounded,
                              size: 14,
                              color: cs.onSecondaryContainer,
                            ),
                          if (_isPremium) const SizedBox(width: 4),
                          Text(
                            _isPremium ? 'Premium' : 'Free',
                            style: tt.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _isPremium
                                  ? cs.onSecondaryContainer
                                  : cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Subject • class label
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.subject} \u2022 ${item.classLevel}',
                              style: tt.labelMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                                letterSpacing: 0.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_isPremium)
                            const SizedBox(width: 8),
                          if (_isPremium)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.1),
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusLg),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.toll_rounded,
                                    size: 14,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${item.creditCost} Credits',
                                    style: tt.labelMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: cs.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Title
                      Text(
                        item.title,
                        style: tt.titleLarge?.copyWith(
                          color: cs.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Description
                      Expanded(
                        child: Text(
                          item.description,
                          style: tt.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Author footer
                      Container(
                        padding:
                            const EdgeInsets.only(top: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color:
                                  cs.outlineVariant.withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(
                                    AppTheme.radiusFull),
                              ),
                              child: Center(
                                child: Text(
                                  getInitials(item.authorName),
                                  style: tt.labelSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: cs.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item.authorName,
                                style: tt.labelLarge?.copyWith(
                                  color: cs.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
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
    );
  }
}

// ---------------------------------------------------------------------------
// Thumbnail Placeholder
// ---------------------------------------------------------------------------
class _ThumbnailPlaceholder extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme tt;
  final VaultItem item;

  const _ThumbnailPlaceholder({
    required this.cs,
    required this.tt,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.description_rounded,
            size: 48,
            color: cs.primary.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom Navigation (Mobile)
// ---------------------------------------------------------------------------
class _BottomNav extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme tt;

  const _BottomNav({required this.cs, required this.tt});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _bottomItem(
            cs: cs,
            tt: tt,
            icon: Icons.home_outlined,
            label: 'Home',
            isActive: false,
            onTap: () => context.go('/'),
          ),
          _bottomItem(
            cs: cs,
            tt: tt,
            icon: Icons.menu_book_rounded,
            label: 'Lessons',
            isActive: false,
            onTap: () => context.go('/lessons'),
          ),
          _bottomItem(
            cs: cs,
            tt: tt,
            icon: Icons.quiz_outlined,
            label: 'Exams',
            isActive: false,
            onTap: () => context.go('/exams'),
          ),
          _bottomItem(
            cs: cs,
            tt: tt,
            icon: Icons.inventory_2_rounded,
            label: 'Vault',
            isActive: true,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _bottomItem({
    required ColorScheme cs,
    required TextTheme tt,
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    if (isActive) {
      return Container(
        width: 80,
        height: 64,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: cs.secondaryContainer,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: cs.onSecondaryContainer,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: tt.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      width: 64,
      height: 64,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: tt.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
