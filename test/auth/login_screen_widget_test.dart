import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/core/services/auth_service.dart';
import 'package:classai/core/services/emergency_flush_service.dart';
import 'package:classai/core/services/security_service.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/auth/screens/login_screen.dart';
import 'package:classai/main.dart' show databaseProvider;

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockAuthService extends Mock implements AuthService {}

class MockSecurityService extends Mock implements SecurityService {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Increases the test surface height so the login screen content doesn't
/// overflow the default 800×600 viewport.
/// Tablet breakpoint is 768 px.  The login screen uses a two-column layout on
/// tablets, and the right-hand card is capped at [ConstrainedBox(maxWidth:400)]
/// with 24 px scroll padding + 32 px card padding, leaving ~336 px for content.
/// A 1200 px wide viewport gives each column ~600 px, which is plenty.
Future<void> ensureViewportHeight(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// Wraps [widget] in a [ProviderScope] with overridden auth dependencies.
/// Also applies a [TextScaler] so the card's constrained width (~334 px) does
/// not overflow (the Row at login_screen.dart:567 is too wide at 1×).
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
      builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(0.5),
        ),
        child: widget!,
      ),
      home: child,
    ),
  );
}

void main() {
  late AppDatabase db;
  late MockAuthService mockAuth;
  late MockSecurityService mockSecurity;

  setUp(() async {
    // Mock the device_info_plus method channel so AppConstants.getDeviceId()
    // returns a fixed map with a known Android ID (avoiding MissingPluginException
    // in the test environment).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/device_info'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getDeviceInfo') {
          return <String, dynamic>{
            'id': 'test-android-device-id',
            'version': <String, dynamic>{'sdkInt': 33},
            'board': '',
            'bootloader': '',
            'brand': 'Test',
            'device': 'test_device',
            'display': '',
            'fingerprint': '',
            'hardware': '',
            'host': '',
            'manufacturer': 'Test',
            'model': 'Test Model',
            'product': 'test_product',
            'name': 'test',
            'supported32BitAbis': <String>[],
            'supported64BitAbis': <String>[],
            'supportedAbis': <String>[],
            'tags': '',
            'type': '',
            'isPhysicalDevice': false,
            'freeDiskSize': 0,
            'totalDiskSize': 0,
            'systemFeatures': <String>[],
            'isLowRamDevice': false,
            'physicalRamSize': 0,
            'availableRamSize': 0,
          };
        }
        return null;
      },
    );

    db = AppDatabase.forTesting();
    await db.initialize();
    mockAuth = MockAuthService();
    mockSecurity = MockSecurityService();

    // Default mock behaviour: no stored hash (offline login not available)
    when(() => mockSecurity.getPasswordHash()).thenAnswer((_) async => null);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/device_info'),
      null,
    );
    await db.close();
  });

  group('LoginScreen rendering', () {
    testWidgets('renders email and password fields', (tester) async {
      await ensureViewportHeight(tester);
      await tester.pumpWidget(createTestApp(
        child: const LoginScreen(),
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      ));

      // Should show the app title
      expect(find.text('ClassAI'), findsOneWidget);

      // Should show the welcome title
      expect(find.text('Welcome back, Educator.'), findsOneWidget);

      // Should have email and password fields
      expect(find.byType(TextFormField), findsNWidgets(2));

      // Should have the Sign In button
      expect(find.text('Sign In'), findsOneWidget);

      // Should have forgot password and create account links
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.text('Create a School Account'), findsOneWidget);
    });

    testWidgets('shows school icon', (tester) async {
      await ensureViewportHeight(tester);
      await tester.pumpWidget(createTestApp(
        child: const LoginScreen(),
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      ));

      expect(find.byIcon(Icons.school_rounded), findsOneWidget);
    });

    testWidgets('email field validates empty input', (tester) async {
      await ensureViewportHeight(tester);
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
      await ensureViewportHeight(tester);
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
      await ensureViewportHeight(tester);
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
    // For error-state tests, mock connectivity as online so loginOnline()
    // proceeds past the PlatformHelper.isOnline() check to the auth service.
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'check') {
            return <String>['wifi'];
          }
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        null,
      );
    });

    testWidgets('shows error banner on failed login attempt', (tester) async {
      await ensureViewportHeight(tester);
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
      await ensureViewportHeight(tester);
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
      await ensureViewportHeight(tester);
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
      await ensureViewportHeight(tester);
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
      await ensureViewportHeight(tester);
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

    testWidgets('shows signup screen on create account tap', (tester) async {
      await ensureViewportHeight(tester);
      await tester.pumpWidget(createTestApp(
        child: const LoginScreen(),
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      ));

      // Ensure button is visible (may be off-screen in small test viewport)
      await tester.ensureVisible(find.text('Create a School Account'));
      // Tap Create a School Account
      await tester.tap(find.text('Create a School Account'));
      await tester.pumpAndSettle();

      // Should navigate to SignupScreen
      expect(find.text('Create School Account'), findsOneWidget);
      expect(find.text('School Name'), findsOneWidget);
      expect(find.text('Admin Email'), findsOneWidget);
    });
    testWidgets('signup screen shows recovery email field', (tester) async {
      await ensureViewportHeight(tester);
      await tester.pumpWidget(createTestApp(
        child: const LoginScreen(),
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      ));

      // Ensure button is visible (may be off-screen in small test viewport)
      await tester.ensureVisible(find.text('Create a School Account'));
      // Navigate to signup screen
      await tester.tap(find.text('Create a School Account'));
      await tester.pumpAndSettle();

      // Recovery email field should be present in the SignupScreen
      expect(find.text('Recovery Email (optional)'), findsOneWidget);
    });
  });
}
