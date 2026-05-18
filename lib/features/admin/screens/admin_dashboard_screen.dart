// lib/features/admin/screens/admin_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/features/admin/providers/admin_provider.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/core/services/auth_service.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Admin dashboard screen with teacher management, vault approval queue,
/// and sync health overview.
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(adminDashboardProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboardData = ref.watch(adminDashboardProvider);
    final authData = ref.watch(authProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Teachers (${dashboardData.teachers.length})'),
            Tab(
              text: 'Vault Queue (${dashboardData.pendingVaultApprovals})',
            ),
            const Tab(text: 'Sync Health'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddTeacherDialog(context),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add Teacher'),
      ),
      body: dashboardData.loading
          ? const Center(child: CircularProgressIndicator())
          : dashboardData.errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Error: ${dashboardData.errorMessage}',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () =>
                            ref.read(adminDashboardProvider.notifier).refresh(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _TeacherManagementTab(
                      teachers: dashboardData.teachers,
                      authData: authData,
                    ),
                    _VaultApprovalTab(authData: authData),
                    _SyncHealthTab(
                      teachers: dashboardData.teachers,
                      dashboardData: dashboardData,
                    ),
                  ],
                ),
    );
  }

  /// Shows the "Add Teacher" dialog.
  void _showAddTeacherDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _AddTeacherDialog(),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Teacher added. A temporary password has been emailed.',
          ),
        ),
      );
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
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Add Teacher'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Error message
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                      fontSize: 13,
                    ),
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
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an email';
                  }
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                      .hasMatch(value.trim())) {
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
                  border: OutlineInputBorder(),
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
                  border: OutlineInputBorder(),
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
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}


// ---------------------------------------------------------------------------
// Teacher Management Tab
// ---------------------------------------------------------------------------

class _TeacherManagementTab extends ConsumerWidget {
  final List<TeacherAdminData> teachers;
  final AuthStateData authData;

  const _TeacherManagementTab({
    required this.teachers,
    required this.authData,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (teachers.isEmpty) {
      return const Center(child: Text('No teachers found.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: teachers.length,
      itemBuilder: (context, index) {
        final teacher = teachers[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: _StatusDot(color: _statusColor(teacher.statusColor)),
            title: Text(teacher.teacherName),
            subtitle: Text(
              '${teacher.email} • ${teacher.role}'
              '${teacher.deviceCount > 0 ? ' • ${teacher.deviceCount} device(s)' : ''}'
              ' • Last sync: ${teacher.formattedLastSync}',
              style: theme.textTheme.bodySmall,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              context.push('/admin/teachers/${teacher.localId}');
            },
          ),
        );
      },
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.orange;
      case 'red':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

// ---------------------------------------------------------------------------
// Vault Approval Tab
// ---------------------------------------------------------------------------

class _VaultApprovalTab extends ConsumerWidget {
  final AuthStateData authData;

  const _VaultApprovalTab({required this.authData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Tier gate: Standard+ required for vault approval queue visibility
    final tier = authData.currentSchool?.subscriptionTier ?? 'free';
    final approvedTiers = ['standard', 'elite'];
    if (!approvedTiers.contains(tier.toLowerCase())) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Vault approval queue requires a Standard or Elite subscription.',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return FutureBuilder(
      future: ref.read(databaseProvider).vaultItemsDao.getPendingApproval(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = snapshot.data ?? [];

        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 64, color: Colors.green.shade300),
                const SizedBox(height: 16),
                Text(
                  'No pending approvals',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'By ${item.authorName} • ${item.subject} • ${item.classLevel}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () =>
                              _rejectItem(context, ref, item.id),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          child: const Text('Reject'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () =>
                              _approveItem(context, ref, item.id),
                          child: const Text('Approve'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _approveItem(
      BuildContext context, WidgetRef ref, int itemId) async {
    await ref.read(databaseProvider).vaultItemsDao.approve(itemId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item approved')),
      );
    }
  }

  Future<void> _rejectItem(
      BuildContext context, WidgetRef ref, int itemId) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => _RejectionDialog(),
    );
    if (reason != null && reason.isNotEmpty) {
      await ref.read(databaseProvider).vaultItemsDao.reject(itemId, reason);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item rejected')),
        );
      }
    }
  }
}

class _RejectionDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();
    return AlertDialog(
      title: const Text('Rejection Reason'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          hintText: 'Enter reason for rejection...',
          border: OutlineInputBorder(),
        ),
        maxLines: 3,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sync Health Tab
// ---------------------------------------------------------------------------

class _SyncHealthTab extends StatelessWidget {
  final List<TeacherAdminData> teachers;
  final AdminDashboardData dashboardData;

  const _SyncHealthTab({required this.teachers, required this.dashboardData});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (teachers.isEmpty) {
      return const Center(child: Text('No teacher data available.'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sync Overview',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _SyncStatRow(
                  label: 'Online (last hour)',
                  count: teachers.where((t) => t.statusColor == 'green').length,
                  color: Colors.green,
                ),
                _SyncStatRow(
                  label: 'Recent (1-24 hrs)',
                  count: teachers.where((t) => t.statusColor == 'yellow').length,
                  color: Colors.orange,
                ),
                _SyncStatRow(
                  label: 'Stale (>24 hrs)',
                  count: teachers.where((t) => t.statusColor == 'red').length,
                  color: Colors.red,
                ),
                _SyncStatRow(
                  label: 'Inactive (>7 days)',
                  count: teachers.where((t) => t.statusColor == 'gray').length,
                  color: Colors.grey,
                ),
                const Divider(height: 24),
                _SyncStatRow(
                  label: 'Pending sync entries',
                  count: dashboardData.teachers.isNotEmpty ? dashboardData.teachers.first.pendingSyncCount : 0,
                  color: Colors.orange,
                ),
                _SyncStatRow(
                  label: 'Unresolved conflicts',
                  count: dashboardData.teachers.isNotEmpty ? dashboardData.teachers.first.conflictCount : 0,
                  color: Colors.red,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...teachers.map((teacher) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: _StatusDot(
                    color: _statusColor(teacher.statusColor)),
                title: Text(teacher.teacherName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last sync: ${teacher.lastSyncTime != null ? _formatTime(teacher.lastSyncTime!) : "Never"}',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      'Devices: ${teacher.deviceCount} • '
                      'Pending: ${teacher.pendingSyncCount} • '
                      'Conflicts: ${teacher.conflictCount}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.orange;
      case 'red':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

class _SyncStatRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SyncStatRow({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(
            '$count',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;

  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
