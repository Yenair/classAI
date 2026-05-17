// lib/features/admin/screens/teacher_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/features/admin/providers/admin_provider.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Teacher detail screen showing device list, recovery code generation,
/// deactivation, and subject assignment.
class TeacherDetailScreen extends ConsumerStatefulWidget {
  final int teacherLocalId;

  const TeacherDetailScreen({super.key, required this.teacherLocalId});

  @override
  ConsumerState<TeacherDetailScreen> createState() =>
      _TeacherDetailScreenState();
}

class _TeacherDetailScreenState extends ConsumerState<TeacherDetailScreen> {
  Teacher? _teacher;
  bool _loading = true;
  bool _generatingCode = false;
  String? _generatedCode;
  DateTime? _codeExpiry;

  @override
  void initState() {
    super.initState();
    _loadTeacher();
  }

  Future<void> _loadTeacher() async {
    setState(() => _loading = true);
    try {
      final results = await (ref.read(databaseProvider).select(
              ref.read(databaseProvider).teachers)
            ..where((t) => t.localId.equals(widget.teacherLocalId)))
          .get();
      if (results.isNotEmpty) {
        setState(() => _teacher = results.first);
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _generateRecoveryCode() async {
    if (_teacher?.serverId == null) return;

    setState(() {
      _generatingCode = true;
      _generatedCode = null;
      _codeExpiry = null;
    });

    try {
      final authNotifier = ref.read(authProvider.notifier);
      final currentTeacher = ref.read(authProvider).currentTeacher;

      if (currentTeacher?.serverId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You must be online to generate recovery codes.'),
            ),
          );
        }
        return;
      }

      final code = await authNotifier.generateTeacherRecoveryCode(
        _teacher!.serverId!,
        currentTeacher!.serverId!,
      );

      setState(() {
        _generatedCode = code;
        _codeExpiry = DateTime.now().add(const Duration(hours: 24));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate code: $e')),
        );
      }
    } finally {
      setState(() => _generatingCode = false);
    }
  }

  Future<void> _deactivateTeacher() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate Teacher'),
        content: Text(
          'Are you sure you want to deactivate ${_teacher?.teacherName ?? "this teacher"}? '
          'They will not be able to log in until reactivated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed == true && _teacher != null) {
      await ref
          .read(adminDashboardProvider.notifier)
          .deactivateTeacher(_teacher!.localId);
      await _loadTeacher();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Teacher deactivated')),
        );
      }
    }
  }

  Future<void> _reactivateTeacher() async {
    if (_teacher != null) {
      await ref
          .read(adminDashboardProvider.notifier)
          .reactivateTeacher(_teacher!.localId);
      await _loadTeacher();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Teacher reactivated')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Teacher Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_teacher == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Teacher Details')),
        body: const Center(child: Text('Teacher not found.')),
      );
    }

    final teacher = _teacher!;

    return Scaffold(
      appBar: AppBar(
        title: Text(teacher.teacherName),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Teacher info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(
                          teacher.teacherName.isNotEmpty
                              ? teacher.teacherName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              teacher.teacherName,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              teacher.email,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: teacher.isActive
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          teacher.isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            color: teacher.isActive
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(),
                  _InfoRow(label: 'Role', value: teacher.role),
                  _InfoRow(
                      label: 'Server ID',
                      value: teacher.serverId ?? 'N/A'),
                  _InfoRow(
                      label: 'Created',
                      value: _formatDate(teacher.createdAt)),
                  _InfoRow(
                      label: 'Updated',
                      value: _formatDate(teacher.updatedAt)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Recovery Code section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recovery Code',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Generate a 16-character recovery code valid for 24 hours. '
                    'The teacher can use this code to reset their password.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (_generatedCode != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.vpn_key,
                                  size: 20, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Recovery Code',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            _generatedCode!,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          if (_codeExpiry != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Expires: ${_formatDate(_codeExpiry!)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.red.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _generatingCode ? null : _generateRecoveryCode,
                      icon: _generatingCode
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : const Icon(Icons.vpn_key),
                      label: Text(
                          _generatingCode ? 'Generating...' : 'Generate Code'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Actions
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Actions',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: teacher.isActive
                        ? FilledButton.icon(
                            onPressed: _deactivateTeacher,
                            icon: const Icon(Icons.block),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            label: const Text('Deactivate Account'),
                          )
                        : FilledButton.icon(
                            onPressed: _reactivateTeacher,
                            icon: const Icon(Icons.check_circle),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            label: const Text('Reactivate Account'),
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Subject Assignment (placeholder for future)
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Subject Assignment',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Subject assignment will be available in a future update.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
