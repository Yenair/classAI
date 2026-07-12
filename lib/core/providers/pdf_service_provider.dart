// lib/core/providers/pdf_service_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/services/pdf_service.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Provider that holds a singleton [PdfService] instance.
///
/// The service depends only on [AppDatabase] for reading lesson/school data,
/// checking daily PDF export limits, and caching generated PDFs.
final pdfServiceProvider = Provider<PdfService>((ref) {
  final db = ref.watch(databaseProvider);
  return PdfService(db);
});
