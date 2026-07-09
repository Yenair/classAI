import 'dart:convert';
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

final selectedSchemeTeacherSelection = ValueNotifier<int?>(null);

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
  bool _isLoadingScheme = false;
  bool _isAdmin = false;
  int? _teacherId;
  int? _schoolId;
  String _teacherName = 'Teacher';
  String _schoolName = 'School';
  String _subscriptionTier = 'free';
  int? _subjectId;
  final Map<int, String> _teacherNamesById = {};
  final Map<int, String> _subjectNamesById = {};
  List<Teacher> _teachers = [];
  int? _adminFilterTeacher; // null = All Teachers

  // Generated SoW data: each entry is {week, topic, objectives}
  List<Map<String, dynamic>> _weeks = [];
  Map<int, TextEditingController> _topicControllers = {};
  Map<int, TextEditingController> _objectivesControllers = {};
  Map<int, TextEditingController> _adminEditControllers = {};

  // Maps week number -> database record ID for loaded schemes
  Map<int, int> _weekRecordIds = {};

  // Existing SoW records
  List<SchemeOfWorkData> _existingSowRecords = [];
  int? _selectedTeacherId;
  String _adminFilterSubject = '';
  String _adminFilterTerm = '';

  final List<String> _terms = ['First', 'Second', 'Third'];

  String _friendlyTerm(String t) {
    switch (t.trim().toLowerCase()) {
      case 'first':
      case '1st':
        return 'First Term';
      case 'second':
      case '2nd':
        return 'Second Term';
      case 'third':
      case '3rd':
        return 'Third Term';
      default:
        return t;
    }
  }
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
      final db = ref.read(databaseProvider);

      // Look up the school by serverId from auth state (not by schoolsDao.get())
      // to ensure we match the correct school record, since schoolsDao.get()
      // returns the first non-deleted school which may not match the admin's school.
      final schoolServerId = authData.currentSchool?.serverId;
      int? resolvedSchoolId;
      if (schoolServerId != null) {
        final schoolByServerId = await (db.select(db.schools)
              ..where((s) => s.serverId.equals(schoolServerId)))
            .getSingleOrNull();
        if (schoolByServerId != null) {
          resolvedSchoolId = schoolByServerId.localId;
          _schoolName = schoolByServerId.schoolName;
          _subscriptionTier = schoolByServerId.subscriptionTier;
        }
      }
      if (resolvedSchoolId == null) {
        final fallbackSchool = await db.schoolsDao.get();
        if (fallbackSchool != null) {
          resolvedSchoolId = fallbackSchool.localId;
          _schoolName = fallbackSchool.schoolName;
          _subscriptionTier = fallbackSchool.subscriptionTier;
        }
      }
      _schoolId = resolvedSchoolId;

      // Reconcile legacy teacher rows before querying, fixing stale schoolLocalId
      await db.reconcileLegacyTeachers();

      final teachers = _schoolId != null
          ? await db.teachersDao.getBySchool(_schoolId!)
          : await db.teachersDao.getAll();
      _teachers = teachers;
      if (teachers.isNotEmpty) {
        final preferredTeacherId = selectedSchemeTeacherSelection.value;
        final teacherIds = teachers.map((t) => t.localId).toSet();
        final selectedTeacher = preferredTeacherId != null &&
                teacherIds.contains(preferredTeacherId)
            ? teachers.firstWhere((t) => t.localId == preferredTeacherId)
            : teachers.first;
        _teacherId = selectedTeacher.localId;
        _selectedTeacherId = selectedTeacher.localId;
        _teacherName = selectedTeacher.teacherName;
      }
      for (final teacher in teachers) {
        _teacherNamesById[teacher.localId] = teacher.teacherName;
      }

      // Preload subject name map for admin filters
      final allSubjects = await db.subjectsDao.getAll();
      for (final subject in allSubjects) {
        _subjectNamesById[subject.id] = subject.name;
      }

      // For admin, preload all school schemes so the filtered view works
      if (_isAdmin && _schoolId != null) {
        await _loadExistingSow();
        debugPrint('[SOW ADMIN] Loaded ${_existingSowRecords.length} total schemes for school $_schoolId');
      }

      if (mounted) {
        await _loadSchemeForSelection();
        setState(() {});
      }
    } catch (_) {}
  }

  Future<List<SchemeOfWorkData>?> _loadExistingSow() async {
    if (_schoolId == null) return null;
    final db = ref.read(databaseProvider);
    try {
      _existingSowRecords = await db.schemeOfWorkDao.getBySchool(_schoolId!);
      debugPrint('[SOW ADMIN] _loadExistingSow returned ${_existingSowRecords.length} records for school $_schoolId');
      return _existingSowRecords;
    } on FormatException catch (e) {
      debugPrint('[SOW] Skipped corrupted scheme_of_work row: $e');
      await db.customStatement(
        "DELETE FROM scheme_of_work WHERE typeof(created_at) != 'integer' OR typeof(updated_at) != 'integer'",
      );
      _existingSowRecords = [];
      return null;
    }
  }

  Future<void> _loadSchemeForSelection() async {
    if (_schoolId == null || _teacherId == null) return;
    setState(() => _isLoadingScheme = true);
    try {
      final db = ref.read(databaseProvider);
      if (_isAdmin) {
        // Admin: reload all school schemes so filters work on full dataset
        await _loadExistingSow();
        final selected = _existingSowRecords
            .where((r) => !r.isDeleted)
            .toList()
          ..sort((a, b) {
            final termCompare = a.term.compareTo(b.term);
            if (termCompare != 0) return termCompare;
            final subjectCompare = a.subjectId.compareTo(b.subjectId);
            if (subjectCompare != 0) return subjectCompare;
            return a.weekNumber.compareTo(b.weekNumber);
          });
        _existingSowRecords = selected;
        _hydrateSchemeRecords(selected);
      } else {
        // Resolve subject name to subjectId
        _subjectId = null;
        final subjectRow = await db.subjectsDao.getByName(_subject);
        if (subjectRow != null) {
          _subjectId = subjectRow.id;
        }

        // Query existing records by school and filter for this teacher + subject + term
        final allSchoolRecords = await db.schemeOfWorkDao.getBySchool(_schoolId!);
        final matching = allSchoolRecords.where((r) =>
            r.teacherId == _teacherId &&
            r.subjectId == _subjectId &&
            r.term == _term &&
            !r.isDeleted).toList()
          ..sort((a, b) => a.weekNumber.compareTo(b.weekNumber));

        _hydrateSchemeRecords(matching);
      }
    } catch (_) {
      // On error, clear weeks to allow generation
      _disposeControllers();
      _weeks = [];
      _weekRecordIds = {};
    } finally {
      if (mounted) setState(() => _isLoadingScheme = false);
    }
  }

  int _normalizeWeekNumber(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();

    final weekText = value?.toString().trim() ?? '';
    if (weekText.isEmpty) return fallback;

    final directNumber = int.tryParse(weekText);
    if (directNumber != null) return directNumber;

    final weekMatch = RegExp(r'week\s*(\d+)', caseSensitive: false)
        .firstMatch(weekText);
    if (weekMatch != null) {
      final matched = int.tryParse(weekMatch.group(1)!);
      if (matched != null) return matched;
    }

    final numericChunk = RegExp(r'\b(\d+)\b').firstMatch(weekText);
    if (numericChunk != null) {
      final matched = int.tryParse(numericChunk.group(1)!);
      if (matched != null) return matched;
    }

    return fallback;
  }

  Map<String, dynamic> _extractSchemePayload(dynamic response) {
    dynamic candidate = response;
    if (candidate is Map<String, dynamic>) {
      candidate = candidate['raw'] ?? candidate['text'] ?? candidate;
    }

    if (candidate is Map<String, dynamic>) {
      return candidate;
    }

    final text = candidate?.toString() ?? '';
    if (text.isEmpty) {
      throw FormatException('Empty scheme response');
    }

    final firstBrace = text.indexOf('{');
    final lastBrace = text.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
      final jsonText = text.substring(firstBrace, lastBrace + 1);
      final decoded = jsonDecode(jsonText);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    }

    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();

    throw FormatException('Scheme response did not contain a JSON object');
  }

  void _hydrateSchemeRecords(List<SchemeOfWorkData> records) {
    _disposeControllers();
    _weeks = [];
    _weekRecordIds = {};

    for (final record in records) {
      final key = _isAdmin ? record.id : record.weekNumber;
      final topicText = _isAdmin &&
              (record.adminEditedTopic != null &&
                  record.adminEditedTopic!.isNotEmpty)
          ? record.adminEditedTopic!
          : record.topic;
      _topicControllers[key] = TextEditingController(text: topicText);
      _objectivesControllers[key] =
          TextEditingController(text: record.objectives);
      _adminEditControllers[record.id] =
          TextEditingController(text: record.adminEditedTopic ?? '');
      _weekRecordIds[record.weekNumber] = record.id;

      _weeks.add({
        'id': record.id,
        'week': record.weekNumber,
        'topic': record.topic,
        'objectives': record.objectives,
        'status': record.status,
        'teacherId': record.teacherId,
        'term': record.term,
        'classLevel': record.classLevel,
        'subjectId': record.subjectId,
        'adminEditedTopic': record.adminEditedTopic,
        'adminComment': record.adminComment,
      });
    }
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
      debugPrint('[SOW] AI response received, length: ${result.length}');
      final rawResponse = result['raw'] ?? result;
      try {
        debugPrint('[SOW] Raw AI response: $rawResponse');
      } catch (_) {}
      final raw = _extractSchemePayload(rawResponse);
      final weeksData = (raw['weeks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      debugPrint('[SOW] Parsed weeks: ${weeksData.length}');

      await aiService.logGeneration(
        teacherId: _teacherId?.toString(),
        schoolId: _schoolId?.toString(),
        topic: 'SoW: $_subject $_term Term',
      );

      // Clear previous controllers
      _disposeControllers();
      debugPrint('[SOW] Calling setState, weeks count: ${_weeks.length}');
      setState(() {
        _weeks = [];
        _topicControllers = {};
        _objectivesControllers = {};
        _adminEditControllers = {};
        _weekRecordIds = {};

        for (final week in weeksData) {
          final weekNum = _normalizeWeekNumber(week['week'], _weeks.length + 1);
          final topic = week['topic'] as String? ?? '';
          final objectives = week['objectives'] as List? ?? [];
          final objStr = objectives.map((e) => e.toString()).join('\n');

          _topicControllers[weekNum] = TextEditingController(text: topic);
          _objectivesControllers[weekNum] =
              TextEditingController(text: objStr);
          _adminEditControllers[weekNum] = TextEditingController();

          _weeks.add({
            'week': weekNum,
            'topic': topic,
            'objectives': objStr,
          });
        }

        _isGenerating = false;
      });
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
      var subjectId = _subjectId;
      if (subjectId == null) {
        final subjectRow = await db.subjectsDao.getByName(_subject);
        subjectId = subjectRow?.id;
      }
      if (subjectId == null) {
        subjectId = await db.subjectsDao.insert(name: _subject);
      }
      _subjectId = subjectId;

      // Resolve server IDs for draft creation
      final teacher = await db.teachersDao.getById(_teacherId!);
      final teacherServerId = teacher?.serverId;
      final school = await db.schoolsDao.get();
      final schoolServerId = school?.serverId;
      final termLabel = _normalizeTermLabelForDraft(_term);

      for (var index = 0; index < _weeks.length; index++) {
        final week = _weeks[index];
        final weekNumber = index + 1;
        final topicText = _topicControllers[weekNumber]?.text ?? week['topic']?.toString() ?? '';
        final objectivesText = _objectivesControllers[weekNumber]?.text ?? week['objectives']?.toString() ?? '';
        final existingId = _weekRecordIds[weekNumber];
        if (existingId != null) {
          // Update existing record
          await db.schemeOfWorkDao.updateWeekEntry(
            existingId,
            topic: topicText,
            objectives: objectivesText,
          );
        } else {
          // Insert new record
          final newId = await db.schemeOfWorkDao.insert(
            SchemeOfWorkCompanion.insert(
              schoolId: Value(_schoolId!),
              teacherId: Value(_teacherId!),
              subjectId: Value(subjectId),
              term: Value(_term),
              classLevel: Value(_classLevel),
              weekNumber: Value(weekNumber),
              topic: Value(topicText),
              objectives: Value(objectivesText),
              status: const Value('draft'),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );
          _weekRecordIds[weekNumber] = newId;
        }

        // Auto-create draft lesson if not already existing
        if (teacherServerId != null && termLabel.isNotEmpty) {
          final existingLessons = await db.lessonsDao.getAll();
          final lessonExists = existingLessons.any((l) =>
              !l.isDeleted &&
              l.teacherServerId == teacherServerId &&
              l.subject == _subject &&
              l.classLevel == _classLevel &&
              (l.term ?? '') == termLabel &&
              (l.weekNumber ?? l.week) == weekNumber &&
              l.status == 'draft');
          if (!lessonExists) {
            await db.lessonsDao.insertLesson(
              LessonsCompanion.insert(
                subject: _subject,
                classLevel: _classLevel,
                week: weekNumber,
                topic: topicText,
                difficulty: 'medium',
                bloomsVerbs: '',
                curriculum: 'NERDC',
                content: jsonEncode({
                  'objectives': [],
                  'vocabulary': [],
                  'materials': [],
                  'presentation': [],
                  'assessment': '',
                  'homework': '',
                }),
                teacherServerId: Value(teacherServerId),
                schoolServerId: schoolServerId != null
                    ? Value(schoolServerId)
                    : const Value.absent(),
                schemeOfWorkId: Value(_weekRecordIds[weekNumber].toString()),
                weekNumber: Value(weekNumber),
                isUnlocked: const Value(false),
                status: const Value('draft'),
                term: Value(termLabel),
              ),
            );
          }

          // Auto-create draft exam if not already existing
          final existingExams = await db.examsDao.getAll();
          final examExists = existingExams.any((e) =>
              !e.isDeleted &&
              e.teacherServerId == teacherServerId &&
              e.subject == _subject &&
              e.classLevel == _classLevel &&
              (e.term ?? '') == termLabel &&
              e.weekNumber == weekNumber);
          if (!examExists) {
            await db.examsDao.insertExam(
              ExamsCompanion.insert(
                subject: _subject,
                classLevel: _classLevel,
                topic: topicText,
                difficulty: 'medium',
                curriculum: 'NERDC',
                content: jsonEncode({
                  'mcqs': [],
                  'theory': [],
                  'subjective': [],
                }),
                teacherServerId: Value(teacherServerId),
                schoolServerId: schoolServerId != null
                    ? Value(schoolServerId)
                    : const Value.absent(),
                isUnlocked: const Value(false),
                schemeOfWorkId: Value(_weekRecordIds[weekNumber].toString()),
                weekNumber: Value(weekNumber),
                term: Value(termLabel),
              ),
            );
          }
        }
      }
      await _loadSchemeForSelection();
      if (mounted) {
        showInfoToast(context: context, message: 'Scheme of Work saved!');
      }
    } catch (e, stackTrace) {
      debugPrint('[SOW] Save failed: $e');
      debugPrint('[SOW] Save stack trace:\n$stackTrace');
      if (mounted) {
        showErrorToast(context: context, message: 'Save failed: $e');
      }
    }
  }

  Future<void> _submitForApproval() async {
    try {
      // Save first to ensure all data is persisted
      await _saveScheme();
      if (_weeks.isEmpty) return;

      final db = ref.read(databaseProvider);
      for (final recordId in _weekRecordIds.values) {
        await db.schemeOfWorkDao.updateStatus(recordId, 'pending');
      }
      await _loadSchemeForSelection();
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
      if (await _hasLessonOrExamReferences(db, schemeWeekId)) {
        await _showReferencedSchemeWarning();
        return;
      }
      final adminEdit = _adminEditControllers[schemeWeekId]?.text.trim();
      final objectiveEdit = _objectivesControllers[schemeWeekId]?.text.trim();
      if (adminEdit != null && adminEdit.isNotEmpty) {
        await db.schemeOfWorkDao.updateAdminEditedTopic(schemeWeekId, adminEdit);
      }
      if (objectiveEdit != null && objectiveEdit.isNotEmpty) {
        await db.schemeOfWorkDao.updateWeekEntry(
          schemeWeekId,
          objectives: objectiveEdit,
        );
      }
      await db.schemeOfWorkDao.updateStatus(schemeWeekId, 'approved');

      // Fetch the approved scheme week to get metadata for draft creation
      final schemeWeek = await db.schemeOfWorkDao.getById(schemeWeekId);
      if (schemeWeek != null) {
        final teacher = await db.teachersDao.getById(schemeWeek.teacherId);
        final teacherServerId = teacher?.serverId;
        final school = await db.schoolsDao.get();
        final schoolServerId = school?.serverId;
        final termLabel = _normalizeTermLabelForDraft(schemeWeek.term);
        final classLevel = schemeWeek.classLevel;
        final subjectRow = await db.subjectsDao.getById(schemeWeek.subjectId);
        final subjectName = subjectRow?.name ?? '';
        final weekNumber = schemeWeek.weekNumber;
        final topic = adminEdit != null && adminEdit.isNotEmpty
            ? adminEdit
            : schemeWeek.topic;

        if (teacherServerId != null &&
            termLabel.isNotEmpty &&
            subjectName.isNotEmpty &&
            classLevel.isNotEmpty) {
          // Check for and create draft lesson
          final existingLessons = await db.lessonsDao.getAll();
          final lessonExists = existingLessons.any((l) =>
              !l.isDeleted &&
              l.teacherServerId == teacherServerId &&
              l.subject == subjectName &&
              l.classLevel == classLevel &&
              (l.term ?? '') == termLabel &&
              (l.weekNumber ?? l.week) == weekNumber &&
              l.status == 'draft');
          if (!lessonExists) {
            await db.lessonsDao.insertLesson(
              LessonsCompanion.insert(
                subject: subjectName,
                classLevel: classLevel,
                week: weekNumber,
                topic: topic,
                difficulty: 'medium',
                bloomsVerbs: '',
                curriculum: 'NERDC',
                content: jsonEncode({
                  'objectives': [],
                  'vocabulary': [],
                  'materials': [],
                  'presentation': [],
                  'assessment': '',
                  'homework': '',
                }),
                teacherServerId: Value(teacherServerId),
                schoolServerId: schoolServerId != null
                    ? Value(schoolServerId)
                    : const Value.absent(),
                schemeOfWorkId: Value(schemeWeekId.toString()),
                weekNumber: Value(weekNumber),
                isUnlocked: const Value(false),
                status: const Value('draft'),
                term: Value(termLabel),
              ),
            );
          }

          // Check for and create draft exam
          final existingExams = await db.examsDao.getAll();
          final examExists = existingExams.any((e) =>
              !e.isDeleted &&
              e.teacherServerId == teacherServerId &&
              e.subject == subjectName &&
              e.classLevel == classLevel &&
              (e.term ?? '') == termLabel &&
              e.weekNumber == weekNumber);
          if (!examExists) {
            await db.examsDao.insertExam(
              ExamsCompanion.insert(
                subject: subjectName,
                classLevel: classLevel,
                topic: topic,
                difficulty: 'medium',
                curriculum: 'NERDC',
                content: jsonEncode({
                  'mcqs': [],
                  'theory': [],
                  'subjective': [],
                }),
                teacherServerId: Value(teacherServerId),
                schoolServerId: schoolServerId != null
                    ? Value(schoolServerId)
                    : const Value.absent(),
                isUnlocked: const Value(false),
                schemeOfWorkId: Value(schemeWeekId.toString()),
                weekNumber: Value(weekNumber),
                term: Value(termLabel),
              ),
            );
          }
        }
      }

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
      if (await _hasLessonOrExamReferences(db, schemeWeekId)) {
        await _showReferencedSchemeWarning();
        return;
      }
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

  Future<bool> _hasLessonOrExamReferences(AppDatabase db, int schemeId) async {
    final schemeIdStr = schemeId.toString();
    final lessonRefs = await (db.select(db.lessons)
          ..where((t) => t.schemeOfWorkId.equals(schemeIdStr))
          ..where((t) => t.isDeleted.equals(false)))
        .get();
    if (lessonRefs.isNotEmpty) return true;

    final examRefs = await (db.select(db.exams)
          ..where((t) => t.schemeOfWorkId.equals(schemeIdStr))
          ..where((t) => t.isDeleted.equals(false)))
        .get();
    return examRefs.isNotEmpty;
  }

  Future<void> _showReferencedSchemeWarning() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scheme in Use'),
        content: const Text(
          'This approved scheme is already linked to lessons or exams. '
          'Please remove those references before editing or deleting it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _normalizeTermLabelForDraft(String term) {
    final cleaned = term.trim();
    if (cleaned.isEmpty) return '';
    final lower = cleaned.toLowerCase();
    if (lower.contains('1st') || lower.contains('first') || lower == '1') {
      return '1st Term';
    }
    if (lower.contains('2nd') || lower.contains('second') || lower == '2') {
      return '2nd Term';
    }
    if (lower.contains('3rd') || lower.contains('third') || lower == '3') {
      return '3rd Term';
    }
    return cleaned;
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
      body: SafeArea(
        child: SingleChildScrollView(

          physics: (Platform.isAndroid || Platform.isIOS)
              ? const BouncingScrollPhysics()
              : null,
          padding: const EdgeInsets.all(16),
          child: _isAdmin
              ? _buildAdminLayout(theme, cs, isWide)
              : isWide
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
      ),
    );
  }

  Widget _buildAdminLayout(ThemeData theme, ColorScheme cs, bool isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAdminHeader(theme, cs),
        const SizedBox(height: 16),
        isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 320,
                    child: _buildTeacherSelectorPanel(theme, cs),
                  ),
                  const SizedBox(width: 24),
                  Expanded(child: _buildAdminView(theme, cs)),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTeacherDropdown(theme, cs),
                  const SizedBox(height: 16),
                  _buildAdminView(theme, cs),
                ],
              ),
      ],
    );
  }

  Widget _buildAdminHeader(ThemeData theme, ColorScheme cs) {
    final selectedTeacher = _selectedTeacherId == null
        ? null
        : _teachers.firstWhere(
            (teacher) => teacher.localId == _selectedTeacherId,
            orElse: () => _teachers.first,
          );

    return Card(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.assignment_rounded,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scheme of Work Review',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selectedTeacher == null
                        ? 'Select a teacher to inspect weekly schemes.'
                        : 'Review and approve ${selectedTeacher.teacherName}\'s weekly scheme entries.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (_selectedTeacherSchemes().isNotEmpty)
              FilledButton.icon(
                onPressed: _bulkApproveSelectedTeacher,
                icon: const Icon(Icons.done_all_rounded),
                label: const Text('Bulk Approve'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherSelectorPanel(ThemeData theme, ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Teachers',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ..._teachers.map(
              (teacher) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildTeacherSelectorTile(theme, cs, teacher),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherSelectorTile(
    ThemeData theme,
    ColorScheme cs,
    Teacher teacher,
  ) {
    final isSelected = teacher.localId == _selectedTeacherId;
    return Material(
      color: isSelected ? cs.primaryContainer.withValues(alpha: 0.35) : cs.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _selectTeacher(teacher.localId),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? cs.primary.withValues(alpha: 0.35)
                  : cs.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: cs.primaryContainer,
                foregroundColor: cs.onPrimaryContainer,
                child: Text(
                  _getInitials(teacher.teacherName),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      teacher.teacherName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      teacher.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected ? Icons.chevron_right_rounded : Icons.chevron_right,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeacherDropdown(ThemeData theme, ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DropdownButtonFormField<int>(
          initialValue: _selectedTeacherId,
          decoration: const InputDecoration(
            labelText: 'Select teacher',
          ),
          items: _teachers
              .map(
                (teacher) => DropdownMenuItem<int>(
                  value: teacher.localId,
                  child: Text(teacher.teacherName),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              _selectTeacher(value);
            }
          },
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _selectedTeacherSchemes() {
    final selectedTeacherId = _selectedTeacherId;
    if (selectedTeacherId == null) return [];
    final records = _weeks.where((weekRecord) {
      return weekRecord['teacherId'] == selectedTeacherId;
    }).toList();
    records.sort(
      (a, b) => (a['week'] as int).compareTo(b['week'] as int),
    );
    return records;
  }

  Future<void> _selectTeacher(int teacherId) async {
    if (_selectedTeacherId == teacherId) return;
    setState(() {
      _selectedTeacherId = teacherId;
      _teacherId = teacherId;
    });
    selectedSchemeTeacherSelection.value = teacherId;
    await _loadSchemeForSelection();
  }

  Future<void> _bulkApproveSelectedTeacher() async {
    final records = _selectedTeacherSchemes()
        .where((record) => (record['status'] as String? ?? 'draft') != 'approved')
        .toList();
    for (final record in records) {
      await _adminApprove(record['id'] as int);
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
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
              onChanged: (v) {
                if (v != null) {
                  setState(() => _subject = v);
                  _loadSchemeForSelection();
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _classLevel,
              decoration: const InputDecoration(labelText: 'Class Level'),
              items: _classLevels.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _classLevel = v);
                  _loadSchemeForSelection();
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _term,
              decoration: const InputDecoration(labelText: 'Term'),
              items: _terms.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _term = v);
                  _loadSchemeForSelection();
                }
              },
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
              // Teacher filter
              DropdownButtonFormField<int?>(
                initialValue: _adminFilterTeacher,
                decoration: const InputDecoration(
                  labelText: 'Filter by Teacher',
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('All Teachers'),
                  ),
                  ..._teachers.map(
                    (teacher) => DropdownMenuItem<int?>(
                      value: teacher.localId,
                      child: Text(teacher.teacherName),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _adminFilterTeacher = v),
              ),
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
                  setState(() {
                    _adminFilterTeacher = null;
                    _adminFilterSubject = '';
                    _adminFilterTerm = '';
                  });
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
    debugPrint('[SOW] build: _weeks length = ${_weeks.length}, _isGenerating = $_isGenerating, _isLoadingScheme = $_isLoadingScheme');
    if (_isAdmin) {
      return _buildAdminView(theme, cs);
    }

    if (_isGenerating || _isLoadingScheme) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_weeks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_month, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text('No scheme generated yet', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 4),
              Text('Configure the options above and tap Generate Scheme',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    // Show teacher's generated/loaded weeks
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Generated Scheme — $_subject $_term Term',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
          ..._weeks.asMap().entries.map((entry) {
            final week = entry.value;
            final weekNum = _normalizeWeekNumber(week['week'], entry.key + 1);
            return _buildWeekCard(
              theme,
              cs,
              weekNum,
              week['topic'] as String,
              week['objectives'] as String,
            );
          }),
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

  Widget _buildAdminView(ThemeData theme, ColorScheme cs) {
    final filtered = _existingSowRecords.where((r) {
      // Teacher filter
      if (_adminFilterTeacher != null && r.teacherId != _adminFilterTeacher) return false;
      // Subject filter: compare by subjectId using the name map
      if (_adminFilterSubject.isNotEmpty) {
        final subjectName = _subjectNamesById[r.subjectId] ?? '';
        if (_adminFilterSubject != subjectName) return false;
      }
      // Term filter
      if (_adminFilterTerm.isNotEmpty && _adminFilterTerm != r.term) return false;
      return true;
    }).toList();

    debugPrint('[SOW ADMIN] _buildAdminView: total=${_existingSowRecords.length}, filtered=${filtered.length}'
        ' teacherFilter=$_adminFilterTeacher subjectFilter=$_adminFilterSubject termFilter=$_adminFilterTerm');

    if (_existingSowRecords.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.assignment_rounded, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text('No schemes submitted yet',
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Ask teachers to generate a scheme of work.',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('No schemes match the current filters.',
              style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
        ),
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
                  child: Text('Week ${record.weekNumber} · ${_friendlyTerm(record.term)}',
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
            Text('Teacher: ${_teacherNamesById[record.teacherId] ?? 'Unknown Teacher'}', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
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
