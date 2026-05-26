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

/// Shared page transition helper.
///
/// Provides a fade-through transition (250ms ease-in-out) that creates a
/// smooth visual flow between screens. The outgoing page fades to transparent
/// while the incoming page fades in — mimicking the Z-axis shared-axis pattern
/// used in Material 3.
CustomTransitionPage _buildPageWithTransition({
  required Widget child,
  required LocalKey key,
}) {
  return CustomTransitionPage(
    key: key,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
  );
}

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
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: const ValueKey('dashboard'),
        child: const DashboardScreen(),
      ),
    ),
    GoRoute(
      path: '/login',
      name: 'login',
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: const ValueKey('login'),
        child: const LoginScreen(),
      ),
    ),
    GoRoute(
      path: '/lessons',
      name: 'lessons',
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: const ValueKey('lessons'),
        child: const LessonsListScreen(),
      ),
    ),
    GoRoute(
      path: '/lessons/:id',
      name: 'lesson-editor',
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: ValueKey('/lessons/${state.pathParameters['id']}'),
        child: const LessonEditorScreen(),
      ),
    ),
    GoRoute(
      path: '/lesson-editor',
      name: 'lesson-creator',
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: const ValueKey('lesson-creator'),
        child: const LessonEditorScreen(),
      ),
    ),
    GoRoute(
      path: '/exams',
      name: 'exams',
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: const ValueKey('exams'),
        child: const ExamsListScreen(),
      ),
    ),
    GoRoute(
      path: '/exams/:id',
      name: 'exam-editor',
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: ValueKey('/exams/${state.pathParameters['id']}'),
        child: const ExamEditorScreen(),
      ),
    ),
    GoRoute(
      path: '/exam-editor',
      name: 'exam-creator',
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: const ValueKey('exam-creator'),
        child: const ExamEditorScreen(),
      ),
    ),
    GoRoute(
      path: '/conflicts',
      name: 'conflicts',
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: const ValueKey('conflicts'),
        child: const ConflictResolutionScreen(),
      ),
    ),
    GoRoute(
      path: '/admin',
      name: 'admin',
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: const ValueKey('admin'),
        child: const AdminDashboardScreen(),
      ),
    ),
    GoRoute(
      path: '/admin/teachers/:id',
      name: 'teacher-detail',
      pageBuilder: (context, state) {
        final teacherLocalId = int.tryParse(state.pathParameters['id'] ?? '');
        if (teacherLocalId == null) {
          return _buildPageWithTransition(
            key: const ValueKey('teacher-detail-error'),
            child: Scaffold(
              appBar: AppBar(title: const Text('Error')),
              body: const Center(child: Text('Invalid teacher ID')),
            ),
          );
        }
        return _buildPageWithTransition(
          key: ValueKey('/admin/teachers/${state.pathParameters['id']}'),
          child: TeacherDetailScreen(teacherLocalId: teacherLocalId),
        );
      },
    ),
    GoRoute(
      path: '/vault',
      name: 'vault',
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: const ValueKey('vault'),
        child: const VaultBrowserScreen(),
      ),
    ),
    GoRoute(
      path: '/vault/publish',
      name: 'vault-publish',
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: const ValueKey('vault-publish'),
        child: const VaultPublisherScreen(),
      ),
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: const ValueKey('settings'),
        child: const SettingsScreen(),
      ),
    ),
    GoRoute(
      path: '/signup',
      name: 'signup',
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: const ValueKey('signup'),
        child: const SignupScreen(),
      ),
    ),
    GoRoute(
      path: '/admin-recovery',
      name: 'admin-recovery',
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: const ValueKey('admin-recovery'),
        child: const AdminRecoveryScreen(),
      ),
    ),
    GoRoute(
      path: '/change-password',
      name: 'change-password',
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: const ValueKey('change-password'),
        child: const ChangePasswordScreen(),
      ),
    ),
    GoRoute(
      path: '/payment',
      name: 'payment',
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: const ValueKey('payment'),
        child: const PaymentScreen(),
      ),
    ),
    GoRoute(
      path: '/insufficient-credit',
      name: 'insufficient-credit',
      pageBuilder: (context, state) => _buildPageWithTransition(
        key: const ValueKey('insufficient-credit'),
        child: const InsufficientCreditScreen(),
      ),
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
