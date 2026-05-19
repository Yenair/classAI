import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:classai/core/constants/curriculum_types.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/features/dashboard/providers/sync_status_provider.dart';
import 'package:classai/features/settings/providers/theme_provider.dart';

/// Settings screen with Account, Credits, Sync, and About sections.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _subjectsKey = 'selected_subjects';
  List<String> _selectedSubjects = List.from(defaultSubjects);
  bool _loadingSubjects = true;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All subjects are already added')),
        );
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Account Section ---
          _SectionHeader(title: 'Account', icon: Icons.person_rounded, cs: cs),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: cs.primary.withValues(alpha: 0.12),
                      child: Icon(
                        Icons.person_rounded,
                        color: cs.primary,
                      ),
                    ),
                    title: Text(
                      authData.currentTeacher?.teacherName ?? 'Teacher',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      authData.currentTeacher?.email ?? '',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                    height: 1,
                  ),
                  const SizedBox(height: 12),
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
                              SnackBar(
                                content: Text('Sign out failed: $e'),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Sign Out'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // --- Credits Section ---
          _SectionHeader(
              title: 'Credits', icon: Icons.monetization_on_outlined, cs: cs),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Current Balance',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      Text(
                        '${creditData.currentCredits}',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.error,
                            ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Purchase Credits — coming soon'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.shopping_cart_outlined),
                      label: const Text('Purchase Credits'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // --- Sync Section ---
          _SectionHeader(title: 'Sync', icon: Icons.sync_rounded, cs: cs),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SyncStatusRow(
                    label: 'Status',
                    value: _syncStatusLabel(syncData.status),
                    icon: _syncStatusIcon(syncData.status),
                    iconColor: _syncStatusColor(syncData.status),
                    cs: cs,
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
                  ),
                  const SizedBox(height: 6),
                  _SyncStatusRow(
                    label: 'Pending pushes',
                    value: '${syncData.pendingPushCount}',
                    icon: Icons.upload_file_rounded,
                    iconColor: cs.onSurfaceVariant,
                    cs: cs,
                  ),
                  if (syncData.lastSyncTime != null) ...[
                    const SizedBox(height: 6),
                    _SyncStatusRow(
                      label: 'Last sync',
                      value: _formatDateTime(syncData.lastSyncTime!),
                      icon: Icons.access_time_rounded,
                      iconColor: cs.onSurfaceVariant,
                      cs: cs,
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: () async {
                        try {
                          await ref.read(syncStatusProvider.notifier).refresh();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Sync status refreshed'),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Sync failed: $e')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Sync Now'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // --- Appearance Section ---
          _SectionHeader(
              title: 'Appearance', icon: Icons.palette_rounded, cs: cs),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Dark Mode'),
              subtitle: const Text('Toggle between light and dark theme'),
              value: Theme.of(context).brightness == Brightness.dark,
              onChanged: (enabled) {
                ref.read(themeProvider.notifier).setTheme(
                      enabled ? ThemeMode.dark : ThemeMode.light,
                    );
              },
            ),
          ),

          // --- Manage Subjects Section ---
          const SizedBox(height: 8),
          _SectionHeader(
              title: 'Manage Subjects',
              icon: Icons.auto_stories_rounded,
              cs: cs),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _loadingSubjects
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Select the subjects your school teaches:',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 12),
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
                    ),
            ),
          ),
          const SizedBox(height: 8),

          // --- About Section ---
          _SectionHeader(
              title: 'About', icon: Icons.info_outline_rounded, cs: cs),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outlined),
                  title: const Text('App Version'),
                  trailing: const Text('1.0.0'),
                ),
                Divider(
                  height: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Privacy Policy — coming soon'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
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

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final ColorScheme cs;

  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}

class _SyncStatusRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final ColorScheme cs;

  const _SyncStatusRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.cs,
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
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
