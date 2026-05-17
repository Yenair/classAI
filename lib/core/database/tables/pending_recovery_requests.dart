import 'package:drift/drift.dart';

/// Tracks teacher password recovery attempts for rate limiting.
/// Enforces 3 attempts per hour per email address.
class PendingRecoveryRequests extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get email => text()();
  DateTimeColumn get attemptedAt => dateTime()();
}

