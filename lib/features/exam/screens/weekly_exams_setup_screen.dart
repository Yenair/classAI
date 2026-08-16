import 'package:classai/core/constants/curriculum_types.dart' show nerdcSubjects;
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/config_provider.dart';
import 'package:classai/core/services/ai_service.dart';
import 'package:classai/core/services/exam_generation_service.dart';
import 'package:classai/core/utils/platform_helper.dart';
import 'package:classai/core/widgets/app_toast.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/dashboard_data_providers.dart'
    show examsListProvider;
import 'package:classai/main.dart' show databaseProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Setup screen for Weekly Exams (13 draft exams, one per week).
///
/// This is the final review step — tapping the explicit `Generate Weekly
/// Exams` button is the only confirmation. There is deliberately no extra
/// confirmation dialog.
class WeeklyExamsSetupScreen extends ConsumerStatefulWidget {
  const WeeklyExamsSetupScreen({super.key});

  @override
  ConsumerState<WeeklyExamsSetupScreen> createState() =>
      _WeeklyExamsSetupScreenState();
}

class _WeeklyExamsSetupScreenState extends ConsumerState<WeeklyExamsSetupScreen> {
  static const _classes = ['JSS 1', 'JSS 2', 'JSS 3', 'SSS 1', 'SSS 2', 'SSS 3'];
  static const _terms = ['1st Term', '2nd Term', '3rd Term'];

  static const _prefSubject = 'weekly_exams_subject';
  static const _prefClass = 'weekly_exams_class';
  static const _prefTerm = 'weekly_exams_term';

  late String _subject;
  late String _classLevel;
  late String _term;
  bool _prefsLoaded = false;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _subject = nerdcSubjects.first;
    _classLevel = _classes.first;
    _term = _terms.first;
    // Pre-fill from the last used values when possible. The dropdowns are
    // only rendered after this resolves so `initialValue` always reflects
    // the loaded values.
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        final savedSubject = prefs.getString(_prefSubject);
        if (savedSubject != null && nerdcSubjects.contains(savedSubject)) {
          _subject = savedSubject;
        }
        final savedClass = prefs.getString(_prefClass);
        if (savedClass != null && _classes.contains(savedClass)) {
          _classLevel = savedClass;
        }
        final savedTerm = prefs.getString(_prefTerm);
        if (savedTerm != null && _terms.contains(savedTerm)) {
          _term = savedTerm;
        }
        _prefsLoaded = true;
      });
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    showErrorToast(context: context, message: message);
  }

  Future<void> _generate() async {
    if (_isGenerating) return;
    setState(() => _isGenerating = true);
    try {
      final db = ref.read(databaseProvider);
      final authState = ref.read(authProvider);
      final school = authState.currentSchool ?? await db.schoolsDao.get();
      final teacherServerId = authState.currentTeacher?.serverId;
      if (school == null || teacherServerId == null) {
        _showError('Teacher or school data not available.');
        return;
      }
      final teacher = await db.teachersDao.findByServerId(teacherServerId);
      if (teacher == null) {
        _showError('Teacher account not ready yet.');
        return;
      }

      final service = ExamGenerationService(db);
      await service.generateWeeklyExams(
        schoolId: school.localId,
        teacherId: teacher.localId,
        teacherServerId: teacherServerId,
        schoolServerId: school.serverId,
        subject: _subject,
        classLevel: _classLevel,
        termLabel: _term,
        subscriptionTier: school.subscriptionTier.toLowerCase(),
        examGenerationAllowedTiers:
            ref.read(configServiceProvider).examGenerationAllowedTiers,
        lessonStorageLimits:
            ref.read(configServiceProvider).lessonStorageLimits,
        aiGenerate: (prompt) async {
          // AI fallback is only reached when no scheme/NERDC topics exist;
          // generation requires internet for that path.
          if (!await PlatformHelper.isOnline()) {
            throw const ExamTopicsUnavailableException();
          }
          return AiService(db: db).generate(prompt);
        },
      );

      // Remember the choices for next time.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefSubject, _subject);
      await prefs.setString(_prefClass, _classLevel);
      await prefs.setString(_prefTerm, _term);

      ref.invalidate(examsListProvider);
      if (!mounted) return;

      // Big success confirmation, then land on the list so the 13 drafts
      // are immediately visible.
      AppToast.instance.showToast(
        context: context,
        message: '13 weekly exam drafts created.',
        icon: Icons.check_circle_rounded,
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      );
      context.go('/exams/list');
    } on ExamTopicsUnavailableException {
      _showError(
        'No topics available for $_subject, $_classLevel, $_term. '
        'Check your internet connection and try again.',
      );
    } on ExamStorageLimitExceededException {
      _showError(
        'Exam storage limit reached. Upgrade your school plan to create '
        'more exams.',
      );
    } on ExamGenerationNotAllowedException {
      _showError('Upgrade to Standard or Elite to generate exams.');
    } catch (e) {
      _showError('Could not create exams: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/exams');
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to exams',
        ),
        title: Text(
          'Weekly Exams Setup',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.12,
          ),
        ),
        elevation: 0,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: cs.surface,
      ),
      body: !_prefsLoaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          // Explanation — exact copy required by the approved plan.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Creates 13 weekly exam drafts. Does not change lessons '
                    'or the scheme of work.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SetupField(
            label: 'Subject',
            value: _subject,
            items: [
              ...nerdcSubjects,
              if (!nerdcSubjects.contains(_subject)) _subject,
            ],
            onChanged: (v) => setState(() => _subject = v),
          ),
          const SizedBox(height: 16),
          _SetupField(
            label: 'Class Level',
            value: _classLevel,
            items: [
              ..._classes,
              if (!_classes.contains(_classLevel)) _classLevel,
            ],
            onChanged: (v) => setState(() => _classLevel = v),
          ),
          const SizedBox(height: 16),
          _SetupField(
            label: 'Term',
            value: _term,
            items: _terms,
            onChanged: (v) => setState(() => _term = v),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isGenerating ? null : _generate,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.calendar_view_week_rounded, size: 20),
              label: Text(
                _isGenerating ? 'Generating...' : 'Generate Weekly Exams',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No extra confirmation — tapping Generate creates the drafts.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SetupField extends StatelessWidget {
  const _SetupField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DropdownButtonFormField<String>(
      initialValue: items.contains(value) ? value : items.first,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: cs.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
