import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'core/constants/app_constants.dart';
import 'core/database/database.dart';
import 'core/database/database_encryption_bootstrap.dart';
import 'core/database/repair_orphaned_scheme_links.dart';
import 'core/services/security_service.dart';
import 'package:classai/core/services/auth_service.dart';
import 'core/services/deep_link_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/dashboard/providers/sync_status_provider.dart'
    show syncStatusProvider;
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/signup_screen.dart';
import 'features/auth/screens/admin_recovery_screen.dart';
import 'features/auth/screens/teacher_recovery_dialog.dart';
import 'features/settings/providers/theme_provider.dart';
import 'core/providers/config_provider.dart';
import 'router/app_router.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final databaseProvider = Provider<AppDatabase>((ref) {
  // Default: return a working AppDatabase instance to prevent crashes
  // from premature access. The real override is set in main() once the
  // database is fully initialized via the UncontrolledProviderScope.
  return AppDatabase();
});

void main() async {
  //TODO: Update Paystack live key 
  //in C:\Users\Yene\classai\supabase\functions\init-payment\index.ts or Supabase secrets before launch!
  
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrint(details.stack.toString());
    }
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('Uncaught error: $error');
    debugPrint(stack.toString());
    return false;
  };

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
  /// Guards against showing multiple quit dialogs on repeated ESC presses.
  bool _quitDialogShowing = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _quitDialogShowing = false;
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

      // Nothing to pop — show the quit confirmation dialog (ESC on the
      // dashboard home or any route that cannot be popped further).
      if (mounted && !_quitDialogShowing) {
        _showQuitConfirmation(context);
      }
    });
    return true;
  }

  void _showQuitConfirmation(BuildContext ctx) {
    _quitDialogShowing = true;
    showDialog<void>(
      context: ctx,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quit ClassAI?'),
        content: const Text('Are you sure you want to quit the app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              SystemNavigator.pop();
            },
            child: const Text('Quit'),
          ),
        ],
      ),
    ).then((_) {
      // Reset the guard regardless of how the dialog was dismissed
      // (Cancel, Quit, ESC, tap outside, system back).
      _quitDialogShowing = false;
    });
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
  bool _isWiping = false;
  /// Guards against showing the key-mismatch recovery dialog more than once.
  bool _keyMismatchDialogShown = false;

  Future<AppDatabase> _initDatabase() async {
    final db = AppDatabase();
    await db.initialize();
    await db.reconcileLegacyTeachers();

    // One-time repair for orphaned scheme-of-work links. Runs once (guarded by
    // a SharedPreferences flag internally) and is fire-and-forget so it never
    // delays app startup; failures are logged but never crash the app.
    unawaited(
      repairOrphanedSchemeLinks(db, force: false).catchError((Object e) {
        debugPrint('Orphaned scheme-link repair failed: $e');
        return 0;
      }),
    );

    return db;
  }

  void _retry() {
    setState(() {
      _databaseFuture = _initDatabase();
    });
  }

  /// Erases all local data (the encrypted database and its sidecars), clears
  /// the stored encryption passphrase + cached auth credentials from secure
  /// storage, then re-initialises a fresh database. On the next launch the
  /// user signs in again and all data is re-downloaded from the server.
  ///
  /// [dialogContext] must be a context that sits under a Navigator (the
  /// bootstrapper's own context is above the MaterialApp it returns, so it is
  /// passed from a [Builder] inside the error screen).
  Future<void> _wipeAndReDownload(BuildContext dialogContext) async {
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-download your data?'),
        content: const Text(
          'This will erase all data stored on this device, including the '
          'database that failed to open, and then download a fresh copy from '
          'your account.\n\n'
          'You will be asked to sign in again. Any unsynced local edits will '
          'be lost.\n\n'
          'Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Erase & Re-download'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isWiping = true);

    try {
      // 1. Delete the database file(s) and the encryption bootstrap marker.
      final dbDirectory = (await getApplicationDocumentsDirectory()).path;
      const candidates = [
        'classai.db',
        'classai.db-wal',
        'classai.db-shm',
        'classai_encrypted.db',
        'classai_encrypted.db-wal',
        'classai_encrypted.db-shm',
        'classai_encryption_state',
      ];
      for (final name in candidates) {
        final file = File(p.join(dbDirectory, name));
        if (file.existsSync()) file.deleteSync();
      }

      // 2. Clear the stored encryption passphrase and cached auth credentials
      //    so a fresh DB is created and the user must sign in again.
      try {
        await SecurityService().clearAll();
      } catch (_) {
        // Best-effort: if clearing secure storage fails, the DB re-creation
        // still proceeds and a fresh passphrase matching the new DB is used.
      }

      if (!mounted) return;
      _retry();
    } catch (e) {
      debugPrint('Failed to wipe local data: $e');
      if (mounted) {
        setState(() => _isWiping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not wipe local data: $e')),
        );
      }
    }
  }

  /// Show the dedicated encryption key-mismatch screen and drive recovery.
  ///
  /// Called when database init threw a [DbKeyMismatchException]. The original
  /// encrypted file has ALREADY been renamed (quarantined) by the bootstrap —
  /// nothing is deleted yet. Here we present the user with an explicit choice:
  ///   - Confirm: clear the passphrase + auth credentials, delete the
  ///     quarantined files, reset the bootstrap marker, and re-initialise a
  ///     fresh database (new key + empty DB -> fresh login + re-download).
  ///   - Cancel: leave the quarantine in place and exit the app. Nothing
  ///     destructive happens, so an administrator can later recover the data.
  Future<void> _handleKeyMismatch(
      BuildContext dialogContext, DbKeyMismatchException mismatch) async {
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Local data could not be opened'),
        content: const Text(
          'Your local data could not be opened, likely due to a security key '
          'issue. You\'ll need to sign in again and your device will '
          're-download your school\'s data.\n\n'
          'The existing data has been quarantined and can be recovered by an '
          'administrator if needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirmed != true) {
      // Cancel: keep the quarantine, leave the passphrase intact, and exit so
      // no destructive action happens without explicit consent.
      SystemNavigator.pop();
      return;
    }

    setState(() => _isWiping = true);

    try {
      final dbDirectory = (await getApplicationDocumentsDirectory()).path;

      // 1. Delete the already-quarantined files (safe now: the user confirmed,
      //    and they live under the quarantine name, not the live classai.db).
      //    Also remove any leftover temp/state files so a fresh DB can be made.
      await _deleteQuarantinedFiles(dbDirectory, mismatch.quarantineTimestamp);

      // 2. Clear the encryption passphrase so a NEW key is generated next
      //    launch, plus cached auth credentials so the user must sign in again.
      try {
        await SecurityService().clearAuthCredentials();
        await SecurityService().clearDbEncryptionPassphrase();
      } catch (_) {
        // Best-effort: if clearing secure storage fails, the fresh DB created
        // below is opened with whatever passphrase is generated and matches.
      }

      if (!mounted) return;
      _retry();
    } catch (e) {
      debugPrint('Failed to re-initialise after key mismatch: $e');
      if (mounted) {
        setState(() => _isWiping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not recover local data: $e')),
        );
      }
    }
  }

  /// Delete files that were quarantined under the given [timestamp] (the
  /// `classai_quarantined_<timestamp>...` family), plus any leftover encryption
  /// temp/state files. Called only AFTER the user confirms recovery, so it is
  /// safe to delete. Never touches a live `classai.db`.
  Future<void> _deleteQuarantinedFiles(
      String dbDirectory, String timestamp) async {
    const candidates = [
      'classai.db',
      'classai.db-wal',
      'classai.db-shm',
      'classai_encrypted.db',
      'classai_encrypted.db-wal',
      'classai_encrypted.db-shm',
      'classai_encryption_state',
    ];
    for (final name in candidates) {
      final file = File(p.join(dbDirectory, name));
      if (file.existsSync()) file.deleteSync();
    }
    // Delete the quarantined files for this specific timestamp.
    for (final suffix in const ['', '-wal', '-shm']) {
      final file = File(
        p.join(dbDirectory, 'classai_quarantined_$timestamp$suffix.db'),
      );
      if (file.existsSync()) file.deleteSync();
    }
    final stateFile =
        File(p.join(dbDirectory, 'classai_quarantined_${timestamp}_state'));
    if (stateFile.existsSync()) stateFile.deleteSync();
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
          // A key mismatch is a distinct, user-actionable failure: the existing
          // encrypted DB has already been quarantined (renamed, not deleted),
          // and the user must explicitly confirm before any destructive step.
          // Show the dedicated recovery screen BEFORE any other UI.
          if (snapshot.error is DbKeyMismatchException) {
            final mismatch = snapshot.error! as DbKeyMismatchException;
            return MaterialApp(
              title: 'ClassAI',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              // The dialog is shown from a Builder context that sits under this
              // MaterialApp's Navigator (the bootstrapper's own context is above
              // the MaterialApp and has no Navigator ancestor).
              home: Builder(
                builder: (screenCtx) {
                  if (!_keyMismatchDialogShown) {
                    _keyMismatchDialogShown = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _handleKeyMismatch(screenCtx, mismatch);
                    });
                  }
                  return Scaffold(
                    body: Center(
                      child: _isWiping
                          ? const CircularProgressIndicator()
                          : const Text(
                              'Your local data could not be opened, likely due '
                              'to a security key issue.',
                              textAlign: TextAlign.center,
                            ),
                    ),
                  );
                },
              ),
            );
          }

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
                    const SizedBox(height: 12),
                    Builder(
                      builder: (buttonCtx) => Center(
                        child: ElevatedButton.icon(
                          onPressed: _isWiping
                              ? null
                              : () => _wipeAndReDownload(buttonCtx),
                          icon: _isWiping
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download_for_offline_outlined),
                          label: Text(
                            _isWiping
                                ? 'Erasing & Re-downloading...'
                                : 'Download data from server',
                          ),
                        ),
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
        // Wire ConfigService into the DAO so daily limits read remote config.
        db.securityConfigDao
            .setConfigService(_overrideContainer!.read(configServiceProvider));
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

    // Re-evaluate GoRouter's redirect guard whenever auth state changes
    // (login, logout, role change, guest transition, etc.).  Without this
    // the redirect callback only fires on explicit navigation actions, so
    // logout never redirects to the login screen until an unrelated tap.
    ref.listen<AuthStateData>(authProvider, (_, __) {
      goRouterRefreshNotifier.value++;
    });

    // Trigger an immediate sync when the user becomes authenticated
    // (login, email verification, or auto-login). This avoids the 5-minute
    // delay before lessons/exams appear after sign-in.
    ref.listen<AuthState>(
      authProvider.select((s) => s.state),
      (previous, next) {
        if (next == AuthState.authenticated &&
            previous != AuthState.authenticated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(syncStatusProvider.notifier).syncNow();
          });
        }
      },
    );

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
        themeMode: ref.watch(themeProvider),
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
