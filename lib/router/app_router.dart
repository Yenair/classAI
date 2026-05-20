import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/main.dart';
import 'package:classai/core/services/deep_link_service.dart';
import 'package:classai/features/auth/screens/login_screen.dart';
import 'package:classai/features/auth/screens/signup_screen.dart';
import 'package:classai/features/auth/screens/change_password_screen.dart';
import 'package:classai/features/auth/screens/admin_recovery_screen.dart';
import 'package:classai/features/auth/screens/teacher_recovery_dialog.dart';
import 'package:classai/features/dashboard/screens/dashboard_screen.dart';
import 'package:classai/features/settings/screens/conflict_resolution_screen.dart';
import 'package:classai/features/lesson/screens/lesson_editor_screen.dart';
import 'package:classai/features/lesson/screens/lessons_list_screen.dart';
import 'package:classai/features/exam/screens/exam_editor_screen.dart';
import 'package:classai/features/exam/screens/exams_list_screen.dart';
import 'package:classai/features/admin/screens/admin_dashboard_screen.dart';
import 'package:classai/features/admin/screens/teacher_detail_screen.dart';
import 'package:classai/features/vault/screens/vault_browser_screen.dart';
import 'package:classai/features/vault/screens/vault_publisher_screen.dart';
import 'package:classai/features/payment/screens/payment_screen.dart';
import 'package:classai/features/settings/screens/settings_screen.dart';
import 'package:classai/features/credit/screens/insufficient_credit_screen.dart';

/// GoRouter configuration for the ClassAI app.
///
/// Routes:
/// - `/` → Dashboard (platform-gated Editor/Reader layout)
/// - `/login` → Login screen
/// - `/lessons` → Lessons list
/// - `/lessons/:id` → Lesson editor
/// - `/exams` → Exams list
/// - `/exams/:id` → Exam editor
/// - `/conflicts` → Conflict resolution screen
/// - `/admin` → Admin dashboard (teacher management, vault queue, sync health)
/// - `/admin/teachers/:id` → Teacher detail screen
/// - `/vault` → Vault browser (approved items grid with filters)
/// - `/vault/publish` → Vault publisher (submit new item for review)
/// - `/settings` → Settings screen
/// - `/payment` → Payment flow (plan selection)
///
/// Deep links (parsed via [DeepLinkService]):
/// - `classai://reset-password?token=xxx` → TeacherRecoveryDialog
/// - `classai://activate?code=xxx` → SignupScreen
/// - `classai://admin-recovery?token=xxx` → AdminRecoveryScreen
final appRouter = GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: '/',
  debugLogDiagnostics: true,
  routes: [
    GoRoute(
      path: '/',
      name: 'dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/lessons',
      name: 'lessons',
      builder: (context, state) => const LessonsListScreen(),
    ),
    GoRoute(
      path: '/lessons/:id',
      name: 'lesson-editor',
      builder: (context, state) => const LessonEditorScreen(),
    ),
    GoRoute(
      path: '/lesson-editor',
      name: 'lesson-creator',
      builder: (context, state) => const LessonEditorScreen(),
    ),
    GoRoute(
      path: '/exams',
      name: 'exams',
      builder: (context, state) => const ExamsListScreen(),
    ),
    GoRoute(
      path: '/exams/:id',
      name: 'exam-editor',
      builder: (context, state) => const ExamEditorScreen(),
    ),
    GoRoute(
      path: '/exam-editor',
      name: 'exam-creator',
      builder: (context, state) => const ExamEditorScreen(),
    ),
    GoRoute(
      path: '/conflicts',
      name: 'conflicts',
      builder: (context, state) => const ConflictResolutionScreen(),
    ),
    GoRoute(
      path: '/admin',
      name: 'admin',
      builder: (context, state) => const AdminDashboardScreen(),
    ),
    GoRoute(
      path: '/admin/teachers/:id',
      name: 'teacher-detail',
      builder: (context, state) {
        final teacherLocalId = int.tryParse(state.pathParameters['id'] ?? '');
        if (teacherLocalId == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Error')),
            body: const Center(child: Text('Invalid teacher ID')),
          );
        }
        return TeacherDetailScreen(teacherLocalId: teacherLocalId);
      },
    ),
    GoRoute(
      path: '/vault',
      name: 'vault',
      builder: (context, state) => const VaultBrowserScreen(),
    ),
    GoRoute(
      path: '/vault/publish',
      name: 'vault-publish',
      builder: (context, state) => const VaultPublisherScreen(),
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/signup',
      name: 'signup',
      builder: (context, state) => const SignupScreen(),
    ),
    GoRoute(
      path: '/admin-recovery',
      name: 'admin-recovery',
      builder: (context, state) => const AdminRecoveryScreen(),
    ),
    GoRoute(
      path: '/change-password',
      name: 'change-password',
      builder: (context, state) => const ChangePasswordScreen(),
    ),
    GoRoute(
      path: '/payment',
      name: 'payment',
      builder: (context, state) => const PaymentScreen(),
    ),
    GoRoute(
      path: '/insufficient-credit',
      name: 'insufficient-credit',
      builder: (context, state) => const InsufficientCreditScreen(),
    ),
  ],
);

/// Handles parsing and navigation for `classai://` deep links that arrive
/// outside of the GoRouter lifecycle (e.g., cold start, app links stream).
///
/// Returns `true` if the URI was recognised and handled.
/// Safely wraps [uiNavigation] inside [WidgetsBinding.instance.addPostFrameCallback]
/// so it never runs during the widget build phase, preventing the
/// "!_debugLocked" navigator assertion.
void _runAfterBuildFrame(VoidCallback uiNavigation) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    uiNavigation();
  });
}

Future<bool> handleDeepLink(BuildContext context, String uriString) async {
  debugPrint('[DBG] handleDeepLink called with URI: $uriString');
  final parsed = DeepLinkService.parse(uriString);
  if (parsed == null) return false;

  switch (parsed.type) {
    case DeepLinkType.resetPassword:
      debugPrint('[DBG] handleDeepLink -> showDialog (resetPassword)');
      _runAfterBuildFrame(() {
        showDialog(
          context: context,
          builder: (_) => const TeacherRecoveryDialog(),
        );
      });
      return true;

    case DeepLinkType.activate:
      debugPrint('[DBG] handleDeepLink -> context.push(/signup)');
      _runAfterBuildFrame(() {
        context.push('/signup');
      });
      return true;

    case DeepLinkType.adminRecovery:
      debugPrint('[DBG] handleDeepLink -> context.push(/admin-recovery)');
      _runAfterBuildFrame(() {
        context.push('/admin-recovery');
      });
      return true;
  }
}
