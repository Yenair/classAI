// lib/features/admin/screens/admin_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/features/admin/providers/admin_provider.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
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
                    _VaultApprovalTab(),
                    _SyncHealthTab(
                      teachers: dashboardData.teachers,
                    ),
                  ],
                ),
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
              '${teacher.deviceCount > 0 ? ' • ${teacher.deviceCount} device(s)' : ''}',
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
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

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

  const _SyncHealthTab({required this.teachers});

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
                subtitle: Text(
                  'Last sync: ${teacher.lastSyncTime != null ? _formatTime(teacher.lastSyncTime!) : "Never"}',
                  style: theme.textTheme.bodySmall,
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
