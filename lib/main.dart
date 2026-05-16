import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/database/database.dart';
import 'core/theme/app_theme.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError(
    'databaseProvider must be overridden in main() before use'
  );
});

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const ClassAiApp());
}

class ClassAiApp extends StatelessWidget {
  const ClassAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClassAI',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const DatabaseBootstrapper(),
    );
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
          return const Scaffold(
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
          );
        }

        if (snapshot.hasError) {
          final errorText = snapshot.error.toString();
          return Scaffold(
            appBar: AppBar(title: const Text('ClassAI')),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                'Failed to initialize the database.\n\n$errorText',
              ),
            ),
          );
        }

        final db = snapshot.data!;
        return ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
          ],
          child: const DatabaseStatusScreen(),
        );
      },
    );
  }
}

class DatabaseStatusScreen extends StatelessWidget {
  const DatabaseStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ClassAI')),
      body: const Center(child: Text('Database OK')),
    );
  }
}
