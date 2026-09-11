import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:classai/core/theme/app_theme.dart' show AppTheme;

/// One navigation entry for [AppSideNav].
class AppSideNavItem {
  final String label;
  final IconData icon;
  final bool isActive;

  const AppSideNavItem({
    required this.label,
    required this.icon,
    this.isActive = false,
  });
}

/// Shared desktop navigation sidebar — the approved Lesson Editor design.
///
/// Every desktop screen that routes between tabs renders this same widget so
/// the panels look identical across the app:
///
/// - `cs.surface` background with a right `outlineVariant` border;
/// - animated collapse between 256 (open) and 72 (closed);
/// - tappable ClassAI / "Nigerian Academic Partner" header with a chevron;
/// - rounded-16 active pill (`secondaryContainer` + w700 label), 48px+ hit
///   targets, tooltips and semantic labels on every item;
/// - teacher-initials footer under a thin divider.
///
/// The Lesson Editor uses the same item labels ("Home", "Lessons", "Exams"),
/// and this widget's default [onItemTap] handles that routing. Screens can
/// override [onItemTap] to keep their existing navigation behavior.
class AppSideNav extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final String teacherName;
  final bool isOpen;
  final VoidCallback onToggle;
  final List<AppSideNavItem> items;
  final void Function(BuildContext context, String label)? onItemTap;

  const AppSideNav({
    super.key,
    required this.cs,
    required this.theme,
    required this.teacherName,
    required this.isOpen,
    required this.onToggle,
    required this.items,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 768) {
      return const SizedBox.shrink();
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: isOpen ? 256 : 72,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(right: BorderSide(color: cs.outlineVariant)),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: EdgeInsets.fromLTRB(isOpen ? 24 : 8, 24, 8, 0),
                child: Row(
                  mainAxisAlignment: isOpen
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.school_rounded,
                      color: cs.primary,
                      // 24px when collapsed so icon + chevron fit the
                      // 72px rail without overflowing.
                      size: isOpen ? 28 : 24,
                    ),
                    if (isOpen) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ClassAI',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Nigerian Academic Partner',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    Icon(
                      isOpen
                          ? Icons.chevron_left_rounded
                          : Icons.chevron_right_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 48),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: items.map((item) {
                  final foreground = item.isActive
                      ? cs.onSecondaryContainer
                      : cs.onSurfaceVariant;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Semantics(
                      button: true,
                      selected: item.isActive,
                      label: item.label,
                      child: Tooltip(
                        message: item.label,
                        child: Material(
                          color: item.isActive
                              ? cs.secondaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            onTap: () => (onItemTap ?? _defaultNavigate)(
                              context,
                              item.label,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: AppTheme.touchTarget,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  children: [
                                    Icon(item.icon, size: 22, color: foreground),
                                    if (isOpen) ...[
                                      const SizedBox(width: 16),
                                      // Expanded + ellipsis: during the
                                      // 72↔256px open/close animation the
                                      // label width is constrained, and an
                                      // unconstrained Text overflows it.
                                      Expanded(
                                        child: Text(
                                          item.label,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                            color: foreground,
                                            fontWeight: item.isActive
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              height: 1,
              color: cs.outlineVariant,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                isOpen ? 24 : 12,
                20,
                isOpen ? 24 : 12,
                24,
              ),
              child: isOpen
                  ? Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: cs.surfaceContainerHigh,
                          child: Text(
                            _initials(teacherName),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            teacherName.trim().isEmpty
                                ? 'Teacher'
                                : teacherName,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: cs.surfaceContainerHigh,
                        child: Text(
                          _initials(teacherName),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Default routing for the standard Home / Lessons / Exams items — same
  /// behavior as the Lesson Editor sidebar.
  void _defaultNavigate(BuildContext context, String label) {
    switch (label) {
      case 'Home':
        context.go('/');
        break;
      case 'Lessons':
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go('/lessons');
        });
        break;
      case 'Exams':
        context.go('/exams');
        break;
    }
  }

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    // Grapheme-safe first character (crashed on emoji/compound names).
    final values = parts
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();
    return values.isEmpty ? 'T' : values;
  }
}
