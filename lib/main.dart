import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'core/constants/app_constants.dart';
import 'core/database/database.dart';
import 'core/services/auth_service.dart';
import 'core/services/deep_link_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/signup_screen.dart';
import 'features/auth/screens/admin_recovery_screen.dart';
import 'features/auth/screens/teacher_recovery_dialog.dart';
import 'features/settings/providers/theme_provider.dart';
import 'router/app_router.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final databaseProvider = Provider<AppDatabase>((ref) {
  // Default: return a working AppDatabase instance to prevent crashes
  // from premature access. The real override is set in main() once the
  // database is fully initialized via the UncontrolledProviderScope.
  return AppDatabase();
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  // Initialize Sentry for crash/error monitoring.
  await SentryFlutter.init(
    (options) {
      options.dsn =
          'https://e31852d48258815d67f87abe1bf441dc@o4511410305761280.ingest.us.sentry.io/4511410311725056';
      options.tracesSampleRate = 1.0;
    },
    appRunner: () => runApp(const ProviderScope(child: ClassAiApp())),
  );
}

/// Root application widget.
///
/// Wraps the app in a single [ProviderScope] so that Riverpod state is never
/// destroyed by a rebuild. The [DatabaseBootstrapper] handles async DB init
/// and uses [UncontrolledProviderScope] to inject the overrides once ready.
class ClassAiApp extends StatelessWidget {
  const ClassAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const DatabaseBootstrapper();
  }
}

/// Global keyboard listener that intercepts the Escape key at the root of
/// the widget tree. On Escape it first tries to pop the current route via
/// [navigatorKey]; if no route is on top of the navigator (e.g. a modal dialog
/// or bottom sheet is displayed), it falls back to calling
/// `Navigator.maybePop(context)` on the listener's own [BuildContext] so the
/// modal is dismissed.
class _RootKeyboardListener extends StatefulWidget {
  const _RootKeyboardListener({required this.child});

  final Widget child;

  @override
  State<_RootKeyboardListener> createState() => _RootKeyboardListenerState();
}

class _RootKeyboardListenerState extends State<_RootKeyboardListener> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;

    // Defer navigation to after the current frame completes to avoid the
    // "!_debugLocked" navigator assertion when Escape is pressed during
    // a build/layout phase or route transition animation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Try to pop via the global navigator key first.
      final navContext = navigatorKey.currentContext;
      if (navContext != null && Navigator.canPop(navContext)) {
        Navigator.of(navContext).maybePop();
        return;
      }

      // If the navigator cannot pop, attempt to close any open modal
      // (dialog, bottom sheet, etc.) using the listener's own context.
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).maybePop();
      }
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class DatabaseBootstrapper extends StatefulWidget {
  const DatabaseBootstrapper({super.key});

  @override
  State<DatabaseBootstrapper> createState() => _DatabaseBootstrapperState();
}

class _DatabaseBootstrapperState extends State<DatabaseBootstrapper> {
  late Future<AppDatabase> _databaseFuture = _initDatabase();
  ProviderContainer? _overrideContainer;

  Future<AppDatabase> _initDatabase() async {
    final db = AppDatabase();
    await db.initialize();
    await db.reconcileLegacyTeachers();
    return db;
  }

  void _retry() {
    setState(() {
      _databaseFuture = _initDatabase();
    });
  }

  @override
  void dispose() {
    _overrideContainer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppDatabase>(
      future: _databaseFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            title: 'ClassAI',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: const Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Starting ClassAI...'),
                  ],
                ),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          final errorText = snapshot.error.toString();
          // Report the failure to Sentry for monitoring
          Sentry.captureException(
            snapshot.error,
            stackTrace: snapshot.stackTrace,
          );
          return MaterialApp(
            title: 'ClassAI',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: Scaffold(
              appBar: AppBar(title: const Text('ClassAI')),
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      'Failed to initialize the database.\n\n$errorText',
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (snapshot.data == null) {
          return MaterialApp(
            title: 'ClassAI',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: const Scaffold(
              body: Center(child: Text('Unexpected error: no data')),
            ),
          );
        }

        final db = snapshot.data!;
        // Create the override container once and reuse it so that
        // UncontrolledProviderScope is stable across rebuilds.
        _overrideContainer ??= ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            authServiceProvider.overrideWithValue(SupabaseAuthService()),
          ],
        );
        return UncontrolledProviderScope(
          container: _overrideContainer!,
          child: const _RootKeyboardListener(
            child: ClassAiRouterApp(),
          ),
        );
      },
    );
  }
}

/// Root screen shown after database initialisation.
///
/// Watches [authProvider] on startup to determine whether the user is
/// authenticated. Shows a loading indicator while checking, directs new /
/// unauthenticated users to the [LoginScreen], and only mounts the
/// full GoRouter-based app once authenticated.
///
/// Also listens for `classai://` deep links at runtime and routes them
/// to the appropriate screens.
class ClassAiRouterApp extends ConsumerStatefulWidget {
  const ClassAiRouterApp({super.key});

  @override
  ConsumerState<ClassAiRouterApp> createState() => _ClassAiRouterAppState();
}

class _ClassAiRouterAppState extends ConsumerState<ClassAiRouterApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    // Load saved theme preference
    ref.read(themeProvider.notifier).loadTheme();
    // Defer auth check to after the initial build frame to avoid
    // calling markNeedsBuild() on the ProviderScope during its own
    // build phase (which causes a FlutterError).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authProvider.notifier).checkLocalAuth();
    });

    _appLinks = AppLinks();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    // Handle the initial link that launched the app (cold start)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null && mounted) {
        // Defer to after the current build frame so we never call showDialog
        // or Navigator.push during a GoRouter transition, which would trigger
        // the "!_debugLocked" Flutter navigator assertion.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _routeDeepLink(initialUri.toString());
        });
      }
    } catch (_) {
      // No initial link — this is a normal app launch
    }

    // Subscribe to incoming links while the app is already running (warm start)
    _linkSubscription = _appLinks.uriLinkStream.listen((Uri uri) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _routeDeepLink(uri.toString());
        });
      }
    });
  }

  /// Parses [uriString] and navigates to the appropriate screen.
  ///
  /// Uses [Navigator.push] so it works in both the login (plain MaterialApp)
  /// and authenticated (GoRouter) contexts.
  void _routeDeepLink(String uriString) {
    final parsed = DeepLinkService.parse(uriString);
    if (parsed == null) return;

    switch (parsed.type) {
      case DeepLinkType.resetPassword:
        showDialog(
          context: context,
          builder: (_) => const TeacherRecoveryDialog(),
        );
        break;

      case DeepLinkType.activate:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const SignupScreen(),
          ),
        );
        break;

      case DeepLinkType.adminRecovery:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AdminRecoveryScreen(),
          ),
        );
        break;
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authData = ref.watch(authProvider);
    // ── Loading state ──────────────────────────────────────────────────
    // Still checking for stored credentials or performing offline login.
    if (authData.state == AuthState.uninitialized ||
        authData.state == AuthState.checkingLocalAuth ||
        authData.state == AuthState.offlineLoginAttempt) {
      return MaterialApp(
        title: 'ClassAI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Starting ClassAI...'),
              ],
            ),
          ),
        ),
      );
    }

    // ── Emergency saving ───────────────────────────────────────────────
    if (authData.state == AuthState.emergencySaving) {
      return MaterialApp(
        title: 'ClassAI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Saving data before logout...'),
              ],
            ),
          ),
        ),
      );
    }

    // ── Not authenticated — show login screen ──────────────────────────
    // Note: navigatorKey is NOT passed here because it is owned by
    // GoRouter (used in the authenticated state). Sharing the same key
    // between a plain MaterialApp and MaterialApp.router causes GoRouter's
    // internal "_routeMatch" to become null during the widget tree
    // transition, triggering a "Null check operator used on a null value"
    // assertion in go_router/builder.dart.
    if (authData.state != AuthState.authenticated) {
      return MaterialApp(
        title: 'ClassAI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const LoginScreen(),
      );
    }

    // ── Authenticated — show full app with GoRouter ────────────────────
    return MaterialApp.router(
      title: 'ClassAI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeProvider),
      routerConfig: appRouter,
    );
  }
}
