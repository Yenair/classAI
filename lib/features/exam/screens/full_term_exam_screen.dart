// lib/features/exam/screens/full_term_exam_screen.dart
//
// The standalone Full-Term Exam screen was removed in the exams-generation
// redesign (Phase 1). The full-term builder is now the "Term Exam" mode
// inside the exam editor (`/exam-editor?compilationType=termExam`), backed by
// `ExamGenerationService` (topic loading, prompt building, single combined
// exam row + sync entry).
//
// This file keeps a redirect-only shim so any legacy navigation to
// `/full-term-exam` lands in the Term Exam mode instead of a separate
// teacher-facing screen. The route itself is no longer registered in the
// router (app_router.dart redirects it to the exam editor).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Redirect shim — immediately replaces itself with the exam editor in
/// Term Exam mode. Not registered as a route anymore; kept only as a safety
/// net for legacy navigation.
class FullTermExamScreen extends StatefulWidget {
  const FullTermExamScreen({super.key});

  @override
  State<FullTermExamScreen> createState() => _FullTermExamScreenState();
}

class _FullTermExamScreenState extends State<FullTermExamScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.go('/exam-editor?compilationType=termExam');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
