import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/main.dart';
import 'package:classai/core/services/deep_link_service.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
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
import 'package:classai/features/scheme_of_work/screens/scheme_of_work_screen.dart';

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
  redirect: (context, state) {
    // Read role from the auth provider.
    // Only redirect when the GoRouter is mounted (i.e. user is authenticated).
    final container = ProviderScope.containerOf(context, listen: false);
    final authData = container.read(authProvider);
    final role = authData.currentTeacher?.role;
    final location = state.uri.path;

    // If role is null (shouldn't happen in authenticated state), allow navigation.
    if (role == null) return null;

    final isTeacherRoute = location == '/' ||
        location == '/lessons' ||
        location.startsWith('/lessons/') ||
        location == '/lesson-editor' ||
        location == '/exams' ||
        location.startsWith('/exams/') ||
        location == '/exam-editor';
    final isAdminRoute =
        location == '/admin' || location.startsWith('/admin/teachers/');
    final isPaymentRoute = location == '/payment';

    // Override: /scheme-of-work is accessible by both roles so skip redirect
    if (location == '/scheme-of-work') return null;

    if (role == 'admin') {
      // Teacher-only routes — admins should never access these.
      if (isTeacherRoute) return '/admin';
      return null;
    }

    // Non-admin users should never reach admin-only routes.
    if (isAdminRoute) return '/';

    // Payment route is admin-only
    if (isPaymentRoute && role != 'admin') return '/';

    return null; // allow navigation
  },
  routes: [
    _route(
      path: '/',
      name: 'dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),
    _route(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),
    _route(
      path: '/lessons',
      name: 'lessons',
      builder: (context, state) => const LessonsListScreen(),
    ),
    _route(
      path: '/lessons/:id',
      name: 'lesson-editor',
      builder: (context, state) {
        final lessonId = int.tryParse(state.pathParameters['id'] ?? '');
        return LessonEditorScreen(lessonId: lessonId);
      },
    ),
    _route(
      path: '/lesson-editor',
      name: 'lesson-creator',
      builder: (context, state) => const LessonEditorScreen(),
    ),
    _route(
      path: '/exams',
      name: 'exams',
      builder: (context, state) => const ExamsListScreen(),
    ),
    _route(
      path: '/exams/:id',
      name: 'exam-editor',
      builder: (context, state) {
        final examId = int.tryParse(state.pathParameters['id'] ?? '');
        return ExamEditorScreen(examId: examId);
      },
    ),
    _route(
      path: '/exam-editor',
      name: 'exam-creator',
      builder: (context, state) => const ExamEditorScreen(),
    ),
    _route(
      path: '/conflicts',
      name: 'conflicts',
      builder: (context, state) => const ConflictResolutionScreen(),
    ),
    _route(
      path: '/admin',
      name: 'admin',
      builder: (context, state) => const AdminDashboardScreen(),
    ),
    _route(
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
    _route(
      path: '/vault',
      name: 'vault',
      builder: (context, state) => const VaultBrowserScreen(),
    ),
    _route(
      path: '/vault/publish',
      name: 'vault-publish',
      builder: (context, state) => const VaultPublisherScreen(),
    ),
    _route(
      path: '/settings',
      name: 'settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    _route(
      path: '/signup',
      name: 'signup',
      builder: (context, state) => const SignupScreen(),
    ),
    _route(
      path: '/admin-recovery',
      name: 'admin-recovery',
      builder: (context, state) => const AdminRecoveryScreen(),
    ),
    _route(
      path: '/change-password',
      name: 'change-password',
      builder: (context, state) => const ChangePasswordScreen(),
    ),
    _route(
      path: '/payment',
      name: 'payment',
      builder: (context, state) => const PaymentScreen(),
    ),
    _route(
      path: '/insufficient-credit',
      name: 'insufficient-credit',
      builder: (context, state) => const InsufficientCreditScreen(),
    ),
    _route(
      path: '/scheme-of-work',
      name: 'scheme-of-work',
      builder: (context, state) => const SchemeOfWorkScreen(),
    ),
  ],
);

/// Helper that wraps a GoRoute's pageBuilder in a [CustomTransitionPage]
/// with a 250 ms fade-through transition.
GoRoute _route({
  required String path,
  required String name,
  required Widget Function(BuildContext, GoRouterState) builder,
  List<GoRoute> routes = const [],
}) {
  return GoRoute(
    path: path,
    name: name,
    routes: routes,
    pageBuilder: (context, state) => CustomTransitionPage(
      key: state.pageKey,
      child: builder(context, state),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 250),
    ),
  );
}

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
