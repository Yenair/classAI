import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/database/database.dart';
import 'core/services/deep_link_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/teacher_recovery_dialog.dart';
import 'router/app_router.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError(
    'databaseProvider must be overridden in main() before use',
  );
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://zbqhxqnkoggckxoyoqox.supabase.co',
    anonKey: '<anon-key>',
  );

  runApp(const ClassAiApp());
}

/// Root application widget.
///
/// Delegates to [DatabaseBootstrapper] to initialise the database before
/// the GoRouter-based app is mounted.
class ClassAiApp extends StatelessWidget {
  const ClassAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const DatabaseBootstrapper();
  }
}

class DatabaseBootstrapper extends StatefulWidget {
  const DatabaseBootstrapper({super.key});

  @override
  State<DatabaseBootstrapper> createState() => _DatabaseBootstrapperState();
}

class _DatabaseBootstrapperState extends State<DatabaseBootstrapper> {
  late final Future<AppDatabase> _databaseFuture = _initDatabase();

  Future<AppDatabase> _initDatabase() async {
    final db = AppDatabase();
    await db.initialize();
    return db;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppDatabase>(
      future: _databaseFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            title: 'ClassAI',
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
          return MaterialApp(
            title: 'ClassAI',
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: Scaffold(
              appBar: AppBar(title: const Text('ClassAI')),
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  'Failed to initialize the database.\n\n$errorText',
                ),
              ),
            ),
          );
        }

        if (snapshot.data == null) {
          return MaterialApp(
            title: 'ClassAI',
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: const Scaffold(
              body: Center(child: Text('Unexpected error: no data')),
            ),
          );
        }

        final db = snapshot.data!;
        return ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
          ],
          child: const ClassAiRouterApp(),
        );
      },
    );
  }
}

/// Root screen shown after database initialisation.
///
/// Wraps [MaterialApp.router] with [appRouter] for full GoRouter-based
/// navigation. Listens for `classai://` deep links at runtime and routes
/// them to the appropriate screens using GoRouter.
class ClassAiRouterApp extends StatefulWidget {
  const ClassAiRouterApp({super.key});

  @override
  State<ClassAiRouterApp> createState() => _ClassAiRouterAppState();
}

class _ClassAiRouterAppState extends State<ClassAiRouterApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    // Handle the initial link that launched the app (cold start)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null && mounted) {
        _routeDeepLink(initialUri.toString());
      }
    } catch (_) {
      // No initial link — this is a normal app launch
    }

    // Subscribe to incoming links while the app is already running (warm start)
    _linkSubscription = _appLinks.uriLinkStream.listen((Uri uri) {
      if (mounted) {
        _routeDeepLink(uri.toString());
      }
    });
  }

  /// Parses [uriString] and navigates to the appropriate screen.
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
        GoRouter.of(context).go('/activation', extra: parsed.code);
        break;

      case DeepLinkType.adminRecovery:
        GoRouter.of(context).go('/admin-recovery');
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
    return MaterialApp.router(
      title: 'ClassAI',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: appRouter,
    );
  }
}
