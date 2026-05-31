import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/ai_service.dart';
import 'package:classai/core/constants/prompt_templates.dart';
import 'package:classai/core/constants/curriculum_types.dart';
import 'package:classai/core/theme/app_theme.dart';
import 'package:classai/core/widgets/app_toast.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/main.dart' show databaseProvider;

final schemeOfWeeksProvider = FutureProvider.family<List<SchemeOfWorkData>, int>(
  (ref, schoolId) async {
    final db = ref.read(databaseProvider);
    return db.schemeOfWorkDao.getBySchool(schoolId);
  },
);

class SchemeOfWorkScreen extends ConsumerStatefulWidget {
  const SchemeOfWorkScreen({super.key});

  @override
  ConsumerState<SchemeOfWorkScreen> createState() => _SchemeOfWorkScreenState();
}

class _SchemeOfWorkScreenState extends ConsumerState<SchemeOfWorkScreen> {
  String _subject = 'Mathematics';
  String _classLevel = 'JSS 1';
  String _term = 'First';
  bool _isGenerating = false;
  bool _isAdmin = false;
  int? _teacherId;
  int? _schoolId;
  String _teacherName = 'Teacher';
  String _schoolName = 'School';
  String _subscriptionTier = 'free';

  // Generated SoW data: each entry is {week, topic, objectives}
  List<Map<String, dynamic>> _weeks = [];
  Map<int, TextEditingController> _topicControllers = {};
  Map<int, TextEditingController> _objectivesControllers = {};
  Map<int, TextEditingController> _adminEditControllers = {};

  // Existing SoW records
  List<SchemeOfWorkData> _existingSowRecords = [];

  // Filter state for admin view
  String _adminFilterSubject = '';
  String _adminFilterTerm = '';

  final List<String> _terms = ['First', 'Second', 'Third'];
  final List<String> _classLevels = [
    'JSS 1', 'JSS 2', 'JSS 3',
    'SSS 1', 'SSS 2', 'SSS 3',
    'Primary 1', 'Primary 2', 'Primary 3',
    'Primary 4', 'Primary 5', 'Primary 6',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAuthInfo();
    });
  }

  Future<void> _loadAuthInfo() async {
    try {
      final authData = ref.read(authProvider);
      _isAdmin = authData.currentTeacher?.role == 'admin';
      if (authData.currentTeacher?.serverId != null) {
        _teacherName = authData.currentTeacher!.teacherName;
      }
      if (authData.currentSchool != null) {
        _schoolName = authData.currentSchool!.schoolName;
        _subscriptionTier = authData.currentSchool!.subscriptionTier;
      }
      final db = ref.read(databaseProvider);
      final school = await db.schoolsDao.get();
      if (school != null) {
        _schoolId = school.localId;
        _schoolName = school.schoolName;
        _subscriptionTier = school.subscriptionTier;
      }
      final teachers = await db.teachersDao.getAll();
      if (teachers.isNotEmpty) {
        final teacher = teachers.first;
        _teacherId = teacher.localId;
        _teacherName = teacher.teacherName;
      }
      await _loadExistingSow();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadExistingSow() async {
    if (_schoolId == null) return;
    final db = ref.read(databaseProvider);
    _existingSowRecords = await db.schemeOfWorkDao.getBySchool(_schoolId!);
    if (mounted) setState(() {});
  }

  Future<void> _handleGenerate() async {
    setState(() => _isGenerating = true);
    try {
      final db = ref.read(databaseProvider);

      final aiService = AiService(db: db);
      await aiService.checkDailyLimit(_subscriptionTier);

      final prompt = PromptTemplates.schemeOfWork(
        _subject, _classLevel, _term,
        teacherName: _teacherName, schoolName: _schoolName,
      );

      final result = await aiService.generate(prompt);
      final raw = result['raw'] as Map<String, dynamic>? ?? result;
      final weeksData = (raw['weeks'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      await aiService.logGeneration(
        teacherId: _teacherId?.toString(),
        schoolId: _schoolId?.toString(),
        topic: 'SoW: $_subject $_term Term',
      );

      // Clear previous controllers
      _disposeControllers();
      _weeks = [];
      _topicControllers = {};
      _objectivesControllers = {};
      _adminEditControllers = {};

      for (final week in weeksData) {
        final weekNum = week['week'] as int? ?? (_weeks.length + 1);
        final topic = week['topic'] as String? ?? '';
        final objectives = week['objectives'] as List? ?? [];
        final objStr = objectives.map((e) => e.toString()).join('\n');

        _topicControllers[weekNum] = TextEditingController(text: topic);
        _objectivesControllers[weekNum] = TextEditingController(text: objStr);
        _adminEditControllers[weekNum] = TextEditingController();

        _weeks.add({
          'week': weekNum,
          'topic': topic,
          'objectives': objStr,
        });
      }

      setState(() => _isGenerating = false);
      if (mounted) {
        showInfoToast(context: context, message: 'Scheme generated! Edit and save.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        showErrorToast(context: context, message: 'Generation failed: $e');
      }
    }
  }

  Future<void> _saveScheme() async {
    if (_schoolId == null || _teacherId == null) return;
    try {
      final db = ref.read(databaseProvider);
      for (final week in _weeks) {
        await db.schemeOfWorkDao.insert(
          SchemeOfWorkCompanion.insert(
            schoolId: Value(_schoolId!),
            teacherId: Value(_teacherId!),
            subjectId: const Value(0),
            term: Value(_term),
            weekNumber: Value(week['week'] as int),
            topic: Value(_topicControllers[week['week']]?.text ?? week['topic'] as String),
            objectives: Value(_objectivesControllers[week['week']]?.text ?? week['objectives'] as String),
            status: const Value('draft'),
          ),
        );
      }
      await _loadExistingSow();
      if (mounted) {
        showInfoToast(context: context, message: 'Scheme of Work saved!');
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context: context, message: 'Save failed: $e');
      }
    }
  }

  Future<void> _submitForApproval() async {
    try {
      final db = ref.read(databaseProvider);
      for (final record in _groupByTerm()) {
        await db.schemeOfWorkDao.updateStatus(record.id, 'pending');
      }
      await _loadExistingSow();
      if (mounted) {
        showInfoToast(context: context, message: 'Submitted for approval!');
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context: context, message: 'Submit failed: $e');
      }
    }
  }

  Future<void> _adminApprove(int schemeWeekId) async {
    try {
      final db = ref.read(databaseProvider);
      final adminEdit = _adminEditControllers[schemeWeekId]?.text;
      if (adminEdit != null && adminEdit.isNotEmpty) {
        await db.schemeOfWorkDao.updateAdminEditedTopic(schemeWeekId, adminEdit);
      }
      await db.schemeOfWorkDao.updateStatus(schemeWeekId, 'approved');
      await _loadExistingSow();
      if (mounted) {
        showInfoToast(context: context, message: 'Approved!');
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context: context, message: 'Approve failed: $e');
      }
    }
  }

  Future<void> _adminReject(int schemeWeekId) async {
    try {
      final db = ref.read(databaseProvider);
      await db.schemeOfWorkDao.updateStatus(schemeWeekId, 'rejected',
          adminComment: 'Rejected by admin');
      await _loadExistingSow();
      if (mounted) {
        showInfoToast(context: context, message: 'Rejected.');
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context: context, message: 'Reject failed: $e');
      }
    }
  }

  List<SchemeOfWorkData> _groupByTerm() {
    final existing = _existingSowRecords.where(
      (r) => (r.subjectId.toString() == _subject) || (r.term == _term),
    ).toList();
    return existing;
  }

  void _disposeControllers() {
    for (final c in _topicControllers.values) { c.dispose(); }
    for (final c in _objectivesControllers.values) { c.dispose(); }
    for (final c in _adminEditControllers.values) { c.dispose(); }
    _topicControllers = {};
    _objectivesControllers = {};
    _adminEditControllers = {};
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          'Scheme of Work',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.12,
          ),
        ),
        elevation: 0,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: SingleChildScrollView(

        physics: (Platform.isAndroid || Platform.isIOS)
            ? const BouncingScrollPhysics()
            : null,
        padding: const EdgeInsets.all(16),
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildConfigColumn(theme, cs)),
                  const SizedBox(width: 24),
                  Expanded(child: _buildPreviewColumn(theme, cs)),
                ],
              )
            : Column(
                children: [
                  _buildConfigColumn(theme, cs),
                  const SizedBox(height: 24),
                  _buildPreviewColumn(theme, cs),
                ],
              ),
      ),
    );
  }

  Widget _buildConfigColumn(ThemeData theme, ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Configuration',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            // Subject dropdown - use nerdcSubjects
            DropdownButtonFormField<String>(
              initialValue: nerdcSubjects.contains(_subject) ? _subject : nerdcSubjects.first,
              decoration: const InputDecoration(labelText: 'Subject'),
              items: nerdcSubjects.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) { if (v != null) setState(() => _subject = v); },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _classLevel,
              decoration: const InputDecoration(labelText: 'Class Level'),
              items: _classLevels.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) { if (v != null) setState(() => _classLevel = v); },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _term,
              decoration: const InputDecoration(labelText: 'Term'),
              items: _terms.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) { if (v != null) setState(() => _term = v); },
            ),
            const SizedBox(height: 20),
            if (!_isAdmin) ...[
              SizedBox(
                width: double.infinity,
                height: AppTheme.touchTarget,
                child: FilledButton.icon(
                  onPressed: _isGenerating ? null : _handleGenerate,
                  icon: _isGenerating
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                      : const Icon(Icons.auto_awesome),
                  label: Text(_isGenerating ? 'Generating...' : 'Generate Scheme'),
                ),
              ),
              if (_weeks.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: AppTheme.touchTarget,
                  child: OutlinedButton.icon(
                    onPressed: _saveScheme,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Scheme'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _submitForApproval,
                    icon: const Icon(Icons.send),
                    label: const Text('Submit for Approval'),
                  ),
                ),
              ],
            ],
            if (_isAdmin) ...[
              Text('Filter existing schemes',
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _adminFilterSubject.isEmpty ? null : _adminFilterSubject,
                decoration: const InputDecoration(labelText: 'Filter by Subject'),
                items: nerdcSubjects.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _adminFilterSubject = v ?? ''),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _adminFilterTerm.isEmpty ? null : _adminFilterTerm,
                decoration: const InputDecoration(labelText: 'Filter by Term'),
                items: _terms.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _adminFilterTerm = v ?? ''),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  _adminFilterSubject = '';
                  _adminFilterTerm = '';
                  _loadExistingSow();
                },
                child: const Text('Clear Filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewColumn(ThemeData theme, ColorScheme cs) {
    if (_isAdmin) {
      return _buildAdminView(theme, cs);
    }

    if (_isGenerating) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_weeks.isEmpty && _existingSowRecords.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_month, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text('No scheme generated yet', style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      );
    }

    // Show teacher's generated weeks
    if (_weeks.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Generated Scheme — $_subject $_term Term',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ..._weeks.map((week) => _buildWeekCard(theme, cs, week['week'] as int, week['topic'] as String, week['objectives'] as String)),
        ],
      );
    }

    // Show existing saved records
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Saved Schemes', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ..._existingSowRecords.map((r) => _buildExistingWeekCard(theme, cs, r)),
      ],
    );
  }

  Widget _buildWeekCard(ThemeData theme, ColorScheme cs, int week, String topic, String objectives) {
    return Card(
      color: cs.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Week $week',
                      style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _topicControllers[week],
              decoration: const InputDecoration(
                labelText: 'Topic',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _objectivesControllers[week],
              decoration: const InputDecoration(
                labelText: 'Objectives (one per line)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 4,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExistingWeekCard(ThemeData theme, ColorScheme cs, SchemeOfWorkData record) {
    return Card(
      color: _statusColor(record.status, cs).withValues(alpha: 0.08),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Week ${record.weekNumber} · ${record.term}',
                      style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor(record.status, cs),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(record.status,
                      style: TextStyle(color: cs.onPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Topic: ${record.adminEditedTopic ?? record.topic}',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(record.objectives, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminView(ThemeData theme, ColorScheme cs) {
    final filtered = _existingSowRecords.where((r) {
      if (_adminFilterSubject.isNotEmpty && _adminFilterSubject != r.subjectId.toString()) return false;
      if (_adminFilterTerm.isNotEmpty && _adminFilterTerm != r.term) return false;
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text('No schemes to display', style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('All Schemes (Admin)', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ...filtered.map((r) => _buildAdminSchemeCard(theme, cs, r)),
      ],
    );
  }

  Widget _buildAdminSchemeCard(ThemeData theme, ColorScheme cs, SchemeOfWorkData record) {
    return Card(
      color: cs.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Week ${record.weekNumber} · ${record.term}',
                      style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor(record.status, cs),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(record.status,
                      style: TextStyle(color: cs.onPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Teacher Topic: ${record.topic}', style: theme.textTheme.bodyMedium),
            if (record.adminEditedTopic != null && record.adminEditedTopic!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Admin Edited: ${record.adminEditedTopic}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.primary)),
              ),
            const SizedBox(height: 4),
            Text(record.objectives, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Admin Edit Topic (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              controller: _adminEditControllers[record.id] ??= TextEditingController(),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (record.status != 'approved')
                  TextButton.icon(
                    onPressed: () => _adminApprove(record.id),
                    icon: Icon(Icons.check_circle, color: cs.primary),
                    label: const Text('Approve'),
                  ),
                const SizedBox(width: 8),
                if (record.status != 'rejected')
                  TextButton.icon(
                    onPressed: () => _adminReject(record.id),
                    icon: Icon(Icons.cancel, color: cs.error),
                    label: const Text('Reject'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status, ColorScheme cs) {
    switch (status) {
      case 'approved': return Colors.green;
      case 'rejected': return Colors.red;
      case 'pending': return Colors.orange;
      default: return cs.primary;
    }
  }
}
