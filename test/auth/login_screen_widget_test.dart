import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/auth_service.dart';
import 'package:classai/core/services/emergency_flush_service.dart';
import 'package:classai/core/services/security_service.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/auth/screens/login_screen.dart';
import 'package:classai/features/auth/screens/admin_recovery_screen.dart';
import 'package:classai/features/auth/screens/activation_screen.dart';
import 'package:classai/main.dart' show databaseProvider;

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockAuthService extends Mock implements AuthService {}

class MockSecurityService extends Mock implements SecurityService {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps [widget] in a [ProviderScope] with overridden auth dependencies.
Widget createTestApp({
  required Widget child,
  required AppDatabase db,
  required AuthService authService,
  required SecurityService securityService,
  EmergencyFlushService? emergencyFlushService,
}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      authServiceProvider.overrideWithValue(authService),
      securityServiceProvider.overrideWithValue(securityService),
      emergencyFlushServiceProvider
          .overrideWithValue(emergencyFlushService ?? EmergencyFlushService()),
    ],
    child: MaterialApp(
      home: child,
    ),
  );
}

void main() {
  late AppDatabase db;
  late MockAuthService mockAuth;
  late MockSecurityService mockSecurity;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.initialize();
    mockAuth = MockAuthService();
    mockSecurity = MockSecurityService();

    // Default mock behaviour: no stored hash (offline login not available)
    when(() => mockSecurity.getPasswordHash())
        .thenAnswer((_) async => null);
  });

  tearDown(() async {
    await db.close();
  });

  group('LoginScreen rendering', () {
    testWidgets('renders email and password fields', (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const LoginScreen(),
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      ));

      // Should show the app title
      expect(find.text('ClassAI'), findsOneWidget);

      // Should show "Sign in to ClassAI"
      expect(find.text('Sign in to ClassAI'), findsOneWidget);

      // Should have email and password fields
      expect(find.byType(TextFormField), findsNWidgets(2));

      // Should have the Sign In button
      expect(find.text('Sign In'), findsOneWidget);

      // Should have forgot password and activate links
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.text('Activate Account'), findsOneWidget);
    });

    testWidgets('shows school icon', (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const LoginScreen(),
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      ));

      expect(find.byIcon(Icons.school_rounded), findsOneWidget);
    });

    testWidgets('email field validates empty input', (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const LoginScreen(),
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      ));

      // Tap Sign In without entering anything
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      // Should show validation error
      expect(find.text('Please enter your email'), findsOneWidget);
    });

    testWidgets('password field validates empty input', (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const LoginScreen(),
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      ));

      // Enter email but no password
      await tester.enterText(
        find.byType(TextFormField).first,
        'teacher@test.com',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      // Should show password validation error
      expect(find.text('Please enter your password'), findsOneWidget);
    });

    testWidgets('password visibility toggle works', (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const LoginScreen(),
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      ));

      // Password field should be obscured initially
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      // Tap the visibility toggle
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pumpAndSettle();

      // Now should show visibility icon
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });
  });

  group('LoginScreen error states', () {
    testWidgets('shows error banner on failed login attempt', (tester) async {
      when(() => mockAuth.login(any(), any(), any())).thenThrow(
        AuthException(
          code: AuthErrorCode.invalidCredentials,
          message: 'Invalid email or password',
        ),
      );

      await tester.pumpWidget(createTestApp(
        child: const LoginScreen(),
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      ));

      // Fill in credentials
      await tester.enterText(
        find.byType(TextFormField).first,
        'wrong@test.com',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'wrongpassword',
      );

      // Tap Sign In
      await tester.tap(find.text('Sign In'));

      // Wait for async operations (mock login delay + state update)
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      // Should show error icon
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows loading indicator during login', (tester) async {
      // Delay the auth service response to give us time to check loading state
      when(() => mockAuth.login(any(), any(), any())).thenAnswer(
        (_) async {
          await Future.delayed(const Duration(seconds: 2));
          throw AuthException(
            code: AuthErrorCode.invalidCredentials,
            message: 'Invalid',
          );
        },
      );

      await tester.pumpWidget(createTestApp(
        child: const LoginScreen(),
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      ));

      // Fill in credentials
      await tester.enterText(
        find.byType(TextFormField).first,
        'teacher@test.com',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'password123',
      );

      // Tap Sign In
      await tester.tap(find.text('Sign In'));

      // Pump to let the login start
      await tester.pump();

      // Should show loading indicator (CircularProgressIndicator)
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Wait for the delayed response to complete
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('LoginScreen dialogs', () {
    testWidgets('shows role-selection dialog on forgot password tap',
        (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const LoginScreen(),
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      ));

      // Tap Forgot Password
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      // Role-selection dialog should appear
      expect(find.text('Reset Password'), findsOneWidget);
      expect(find.text('Are you an admin or a teacher?'), findsOneWidget);
      expect(find.text("I'm an Admin"), findsOneWidget);
      expect(find.text("I'm a Teacher"), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('tapping "I\'m an Admin" navigates to AdminRecoveryScreen',
        (tester) async {
      when(() => mockAuth.requestAdminOtp(any())).thenAnswer(
        (_) async => AdminRecoveryResult(
          otpSent: true,
          otpExpiry: DateTime.now().add(const Duration(minutes: 10)),
        ),
      );

      await tester.pumpWidget(createTestApp(
        child: const LoginScreen(),
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      ));

      // Tap Forgot Password
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      // Tap "I'm an Admin"
      await tester.tap(find.text("I'm an Admin"));
      await tester.pumpAndSettle();

      // Should navigate to AdminRecoveryScreen
      expect(find.text('Admin Recovery'), findsWidgets);
      expect(find.text('Send OTP'), findsOneWidget);
    });

    testWidgets('tapping "I\'m a Teacher" opens teacher recovery dialog',
        (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const LoginScreen(),
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      ));

      // Tap Forgot Password
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      // Tap "I'm a Teacher"
      await tester.tap(find.text("I'm a Teacher"));
      await tester.pumpAndSettle();

      // Teacher recovery dialog should appear
      expect(find.text('Teacher Recovery'), findsOneWidget);
      expect(find.text('Recovery Code'), findsOneWidget);
      expect(find.text('Reset Password'), findsWidgets);
    });

    testWidgets('shows activation screen on activate account tap',
        (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const LoginScreen(),
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      ));

      // Tap Activate Account
      await tester.tap(find.text('Activate Account'));
      await tester.pumpAndSettle();

      // Should navigate to ActivationScreen
      expect(find.text('Activate Your Account'), findsOneWidget);
      expect(find.text('Activation Code'), findsOneWidget);
      expect(find.text('Account Type'), findsOneWidget);
    });

    testWidgets('activation screen shows recovery email field for admin',
        (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const LoginScreen(),
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      ));

      // Navigate to activation screen
      await tester.tap(find.text('Activate Account'));
      await tester.pumpAndSettle();

      // Default is Teacher, so recovery email should NOT be visible
      expect(find.text('Recovery Email (Required for Admin)'), findsNothing);

      // Scroll down to make the SegmentedButton visible
      await tester.scrollUntilVisible(
        find.text('Admin'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );

      // Toggle to Admin
      await tester.tap(find.text('Admin'));
      await tester.pumpAndSettle();

      // Now recovery email field should appear
      expect(
        find.text('Recovery Email (Required for Admin)'),
        findsOneWidget,
      );
    });
  });
}
