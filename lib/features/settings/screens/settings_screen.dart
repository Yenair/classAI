import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:classai/core/constants/curriculum_types.dart';
import 'package:classai/core/widgets/app_toast.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/features/dashboard/providers/sync_status_provider.dart';
import 'package:classai/features/settings/providers/theme_provider.dart';

/// Settings screen — redesigned to match Google Stitch bento grid layout.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _subjectsKey = 'selected_subjects';
  List<String> _selectedSubjects = List.from(defaultSubjects);
  bool _loadingSubjects = true;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadSubjects();
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
          _appVersion = '1.0.0';
        });
      }
    }
  }

  Future<void> _loadSubjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_subjectsKey);
      if (stored != null) {
        final decoded =
            (jsonDecode(stored) as List).map((e) => e as String).toList();
        if (mounted) {
          setState(() {
            _selectedSubjects = decoded;
            _loadingSubjects = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _loadingSubjects = false);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingSubjects = false);
      }
    }
  }

  Future<void> _saveSubjects() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_subjectsKey, jsonEncode(_selectedSubjects));
  }

  void _addSubject(String subject) {
    setState(() {
      _selectedSubjects.add(subject);
      _selectedSubjects.sort();
    });
    _saveSubjects();
  }

  void _removeSubject(String subject) {
    setState(() {
      _selectedSubjects.remove(subject);
    });
    _saveSubjects();
  }

  Future<void> _showAddSubjectDialog() async {
    final available = nerdcSubjects
        .where((s) => !_selectedSubjects.contains(s))
        .toList()
      ..sort();

    if (available.isEmpty) {
      if (mounted) {
        showInfoToast(
            context: context, message: 'All subjects are already added');
      }
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add Subject'),
        children: available.map((subject) {
          return SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(subject),
            child: Text(subject),
          );
        }).toList(),
      ),
    );

    if (selected != null) {
      _addSubject(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authData = ref.watch(authProvider);
    final creditData = ref.watch(creditStateProvider);
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
            if (isWide) _buildNavDrawer(cs, textTheme, authData),

            // === Main Content ===
            Expanded(
              child: Column(
                children: [
                  // === TopAppBar (mobile + desktop) ===
                  _buildTopAppBar(cs, textTheme, authData, isWide),

                  // === Canvas ===
                  Expanded(
                    child: SingleChildScrollView(
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
                              creditData,
                              syncData,
                              isDark,
                              isWide,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // === BottomNav (mobile only) ===
                  if (!isWide) _buildBottomNav(cs, textTheme),
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
                          authData.currentTeacher?.teacherName ?? 'E'),
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Educator Profile',
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
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _SettingsNavItem(
                    icon: Icons.home_rounded,
                    label: 'Home',
                    isActive: false,
                    cs: cs,
                    textTheme: textTheme),
                const SizedBox(height: 4),
                _SettingsNavItem(
                    icon: Icons.menu_book_rounded,
                    label: 'Lessons',
                    isActive: false,
                    cs: cs,
                    textTheme: textTheme),
                const SizedBox(height: 4),
                _SettingsNavItem(
                    icon: Icons.quiz_rounded,
                    label: 'Exams',
                    isActive: false,
                    cs: cs,
                    textTheme: textTheme),
                const SizedBox(height: 4),
                _SettingsNavItem(
                    icon: Icons.inventory_2_rounded,
                    label: 'Vault',
                    isActive: false,
                    cs: cs,
                    textTheme: textTheme),
                const SizedBox(height: 4),
                _SettingsNavItem(
                    icon: Icons.admin_panel_settings_rounded,
                    label: 'Admin',
                    isActive: false,
                    cs: cs,
                    textTheme: textTheme),
                const SizedBox(height: 4),
                _SettingsNavItem(
                    icon: Icons.settings_rounded,
                    label: 'Settings',
                    isActive: true,
                    cs: cs,
                    textTheme: textTheme),
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
    CreditStateData creditData,
    SyncStatusData syncData,
    bool isDark,
    bool isWide,
  ) {
    return Column(
      children: [
        // Row 1: Interface Mode + Appearance
        isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildInterfaceModeCard(cs, textTheme),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildAppearanceCard(
                        cs, textTheme, isDark),
                  ),
                ],
              )
            : Column(
                children: [
                  _buildInterfaceModeCard(cs, textTheme),
                  const SizedBox(height: 16),
                  _buildAppearanceCard(cs, textTheme, isDark),
                ],
              ),
        const SizedBox(height: 16),

        // Row 2: Account + Credits (side by side on wide)
        isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildAccountCard(
                        context, cs, textTheme, authData),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildCreditsCard(
                        context, cs, textTheme, creditData),
                  ),
                ],
              )
            : Column(
                children: [
                  _buildAccountCard(
                      context, cs, textTheme, authData),
                  const SizedBox(height: 16),
                  _buildCreditsCard(
                      context, cs, textTheme, creditData),
                ],
              ),
        const SizedBox(height: 16),

        // Row 3: Sync (full width)
        _buildSyncCard(
            context, cs, textTheme, syncData),
        const SizedBox(height: 16),

        // Row 4: Manage Subjects (full width)
        _buildSubjectsCard(cs, textTheme),
        const SizedBox(height: 16),

        // Row 5: About + System Actions
        _buildAboutCard(context, cs, textTheme),
      ],
    );
  }

  // ---------------------------------------------------------------
  // Interface Mode Card
  // ---------------------------------------------------------------
  Widget _buildInterfaceModeCard(ColorScheme cs, TextTheme textTheme) {
    return _StitchCard(
      cs: cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.display_settings_rounded,
                size: 28,
                color: cs.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'Interface Mode',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Select your preferred interaction mode for the platform.',
            style: textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _ModeOption(
            label: 'Auto (System Default)',
            value: 'auto',
            groupValue: 'auto',
            cs: cs,
            textTheme: textTheme,
            onChanged: (_) {},
          ),
          const SizedBox(height: 8),
          _ModeOption(
            label: 'Reader (Optimized for grading)',
            value: 'reader',
            groupValue: 'auto',
            cs: cs,
            textTheme: textTheme,
            onChanged: (_) {},
          ),
          const SizedBox(height: 8),
          _ModeOption(
            label: 'Editor (Lesson planning focus)',
            value: 'editor',
            groupValue: 'auto',
            cs: cs,
            textTheme: textTheme,
            onChanged: (_) {},
          ),
        ],
      ),
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
          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),

          // Sign Out button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () async {
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
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign Out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Credits Card
  // ---------------------------------------------------------------
  Widget _buildCreditsCard(BuildContext context, ColorScheme cs,
      TextTheme textTheme, CreditStateData creditData) {
    return _StitchCard(
      cs: cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.monetization_on_outlined,
                size: 28,
                color: cs.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'Credits',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Balance
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Current Balance',
                style: textTheme.bodyLarge,
              ),
              Text(
                '${creditData.currentCredits}',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          if (creditData.loading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          if (creditData.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                creditData.errorMessage!,
                style: textTheme.bodySmall
                    ?.copyWith(color: cs.error),
              ),
            ),
          const SizedBox(height: 16),

          // Purchase button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: () {
                showInfoToast(
                    context: context,
                    message: 'Purchase Credits \u2014 coming soon');
              },
              icon: const Icon(Icons.shopping_cart_outlined),
              label: const Text('Purchase Credits'),
            ),
          ),
        ],
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
                syncData.isOnline ? Colors.green : cs.onSurfaceVariant,
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

          // Sync Now button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: () async {
                try {
                  await ref
                      .read(syncStatusProvider.notifier)
                      .refresh();
                  if (context.mounted) {
                    showInfoToast(
                        context: context,
                        message: 'Sync status refreshed');
                  }
                } catch (e) {
                  if (context.mounted) {
                    showErrorToast(
                        context: context,
                        message:
                            'Failed to refresh sync status: $e');
                  }
                }
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Sync Now'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Manage Subjects Card
  // ---------------------------------------------------------------
  Widget _buildSubjectsCard(ColorScheme cs, TextTheme textTheme) {
    return _StitchCard(
      cs: cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_stories_rounded,
                size: 28,
                color: cs.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'Manage Subjects',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Select the subjects your school teaches:',
            style: textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (_loadingSubjects)
            const Center(child: CircularProgressIndicator())
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedSubjects.map((subject) {
                return Chip(
                  label: Text(subject,
                      style: const TextStyle(fontSize: 13)),
                  deleteIcon:
                      const Icon(Icons.close_rounded, size: 16),
                  onDeleted: () => _removeSubject(subject),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _showAddSubjectDialog,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Subject'),
              ),
            ),
          ],
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
                _appVersion.isEmpty ? '1.0.0' : _appVersion,
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
              showInfoToast(
                  context: context,
                  message:
                      'Privacy Policy \u2014 coming soon');
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
                    onTap: () {
                      showInfoToast(
                          context: context,
                          message:
                              'About ClassAI \u2014 coming soon');
                    },
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
                    onTap: () async {
                      try {
                        await ref
                            .read(authProvider.notifier)
                            .manualLogout();
                        if (context.mounted) {
                          context.go('/login');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Sign out failed: $e')),
                          );
                        }
                      }
                    },
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
  Widget _buildBottomNav(ColorScheme cs, TextTheme textTheme) {
    final items = [
      (icon: Icons.home_rounded, label: 'Home'),
      (icon: Icons.menu_book_rounded, label: 'Lessons'),
      (icon: Icons.quiz_rounded, label: 'Exams'),
      (icon: Icons.more_horiz_rounded, label: 'More'),
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
              onPressed: () {},
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
    switch (status) {
      case SyncStatus.offline:
        return Colors.grey;
      case SyncStatus.syncing:
        return Colors.blue;
      case SyncStatus.synced:
        return Colors.green;
      case SyncStatus.error:
        return Colors.red;
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

  const _SettingsNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.cs,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFFE0E0FF)
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
                ? const Color(0xFF00026C)
                : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 16),
          Text(
            label,
            style: textTheme.labelLarge?.copyWith(
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive
                  ? const Color(0xFF00026C)
                  : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mode Option (Radio)
// ---------------------------------------------------------------------------
class _ModeOption extends StatelessWidget {
  final String label;
  final String value;
  final String groupValue;
  final ColorScheme cs;
  final TextTheme textTheme;
  final ValueChanged<String?> onChanged;

  const _ModeOption({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.cs,
    required this.textTheme,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? cs.primary
                : cs.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? cs.primary : cs.outline,
                  width: 2,
                ),
                color: isSelected ? cs.primary : Colors.transparent,
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
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
          Text(
            '$label:',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
