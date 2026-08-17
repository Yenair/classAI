import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Type colors and icons used wherever an exam type appears (choice cards,
/// list tabs/badges, success content). Kept in one place so the coding stays
/// consistent:
///
/// | Type           | Color  | Icon                      |
/// |----------------|--------|---------------------------|
/// | CA Test        | Blue   | quiz_rounded              |
/// | Term Exam      | Green  | assignment_rounded        |
/// | Weekly Exams   | Orange | calendar_view_week_rounded |
const kCaTestColor = Color(0xFF2196F3);
const kTermExamColor = Color(0xFF4CAF50);
const kWeeklyExamsColor = Color(0xFFFF9800);

/// The two primary creation cards plus the progressive-disclosure link for
/// Weekly Exams. Shared by the `/exams` choice screen and the `/exams/list`
/// zero state so both lead into the exact same setup screens.
class ExamCreationCards extends StatefulWidget {
  const ExamCreationCards({super.key});

  @override
  State<ExamCreationCards> createState() => _ExamCreationCardsState();
}

class _ExamCreationCardsState extends State<ExamCreationCards> {
  bool _weeklyExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExamTypeCard(
          title: 'Term Exam',
          subtitle: 'Make one exam for the term.',
          color: kTermExamColor,
          icon: Icons.assignment_rounded,
          onTap: () => context.push('/exam-editor?compilationType=termExam'),
        ),
        const SizedBox(height: 12),
        ExamTypeCard(
          title: 'CA Test (Class Test)',
          subtitle: 'Make a class test from selected topics.',
          color: kCaTestColor,
          icon: Icons.quiz_rounded,
          onTap: () => context.push('/exam-editor?compilationType=caTest'),
        ),
        const SizedBox(height: 4),
        // Progressive disclosure: stays on screen, toggles the Weekly Exams
        // card inline. The link never navigates away.
        InkWell(
          onTap: () => setState(() => _weeklyExpanded = !_weeklyExpanded),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _weeklyExpanded
                      ? 'More ways to make a test ▴'
                      : 'More ways to make a test ▾',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _weeklyExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: ExamTypeCard(
            title: 'Weekly Exams',
            subtitle: 'Make 13 weekly exam drafts.',
            color: kWeeklyExamsColor,
            icon: Icons.calendar_view_week_rounded,
            onTap: () => context.push('/weekly-exams-setup'),
          ),
        ),
      ],
    );
  }
}

/// One large full-width creation card with an icon, a short sentence and a
/// generous tap target (>= 64 dp).
class ExamTypeCard extends StatelessWidget {
  const ExamTypeCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 26, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The `/exams` screen: decide what to make. Term Exam and CA Test are the
/// two primary paths; Weekly Exams is revealed through progressive disclosure;
/// `View my exams` always routes to the list at `/exams/list`.
class ExamChoiceScreen extends StatelessWidget {
  const ExamChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(
          // History-aware back: pop to the route that opened Exams when there
          // is history (e.g. the dashboard's "Generate Exam" push); only fall
          // back to Home when Exams was reached without history to pop.
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
        ),
        title: Text(
          'Exams',
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          Text(
            'What do you want to make?',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose the kind of exam, then set it up and generate.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          const ExamCreationCards(),
          const SizedBox(height: 28),
          FilledButton.tonalIcon(
            onPressed: () => context.push('/exams/list'),
            icon: const Icon(Icons.list_alt_rounded, size: 20),
            label: const Text('View my exams'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
