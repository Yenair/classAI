import 'dart:isolate';
import 'package:drift/drift.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import '../database/database.dart';
import 'low_storage_service.dart';

class PdfCacheKey {
  final String contentHash;
  final bool applyWatermark;
  final String schoolNameHash;
  final String? logoHash;

  // v2: busts cached PDFs generated before the References section was added
  // so existing lessons re-export with their source references included.
  String get compositeKey =>
      'v2-$contentHash-$applyWatermark-$schoolNameHash-${logoHash ?? "none"}';

  PdfCacheKey({
    required this.contentHash,
    required this.applyWatermark,
    required this.schoolNameHash,
    this.logoHash,
  });
}

class PdfExportException implements Exception {
  final String message;
  final int? remainingCount;
  PdfExportException(this.message, {this.remainingCount});

  @override
  String toString() => 'PDF export limit exceeded: $message';
}

class PdfService {
  final AppDatabase _db;

  PdfService(this._db);

  DateTime? _lastWatermarkCheck;
  bool? _cachedWatermarkRequired;

  /// Check if watermark should be applied.
  /// Cached for 1 hour to avoid excessive heartbeat calls.
  Future<bool> shouldApplyWatermark(School school) async {
    if (_lastWatermarkCheck != null &&
        DateTime.now().difference(_lastWatermarkCheck!) <
            const Duration(hours: 1) &&
        _cachedWatermarkRequired != null) {
      return _cachedWatermarkRequired!;
    }

    // Watermark required if tier is Free, OR if subscription expired
    final tier = school.subscriptionTier.toLowerCase();
    final expired = school.expiryDate != null &&
        school.expiryDate!.isBefore(DateTime.now());
    _cachedWatermarkRequired = tier == 'free' || expired;
    _lastWatermarkCheck = DateTime.now();
    return _cachedWatermarkRequired!;
  }

  /// Check if PDF export is allowed based on daily limit.
  /// Throws [PdfExportException] if limit exceeded.
  Future<bool> checkDailyLimit(String tier) async {
    final allowed = await _db.securityConfigDao
        .checkAndIncrementDailyPdfExports(tier: tier);
    if (!allowed) {
      final remaining =
          await _db.securityConfigDao.getRemainingPdfExports(tier: tier);
      throw PdfExportException(
        'Daily PDF export limit reached.',
        remainingCount: remaining < 0 ? null : remaining,
      );
    }
    return true;
  }

  /// Log an audit entry for PDF export.
  Future<void> logPdfExport(
      {required String? teacherId,
      required String? schoolId,
      required String topic}) async {
    final id = const Uuid().v4();
    await _db.auditLogsDao.insert(
      AuditLogsCompanion.insert(
        id: Value(id),
        teacherId: Value(teacherId),
        schoolId: Value(schoolId),
        action: Value('pdf_export'),
        metadata: Value(jsonEncode({
          'topic': topic,
          'timestamp': DateTime.now().toIso8601String(),
        })),
      ),
    );
  }

  /// Generate a PDF for a lesson. Uses isolate to avoid UI blocking.
  /// Checks disk space before generation; throws [Exception]
  /// if critical (< 100 MB).
  /// Optionally accepts [teacherId] for audit logging and
  /// [teacherEmail] for watermark attribution.
  Future<Uint8List> generateLessonPdf(
    Lesson lesson,
    School school, {
    String? teacherId,
    String? teacherEmail,
  }) async {
    // Check daily PDF export limit before generating
    await checkDailyLimit(school.subscriptionTier);

    // Check disk space before generating
    final storageService = LowStorageService();
    final canGenerate = await storageService.canGeneratePdf();
    if (!canGenerate) {
      throw Exception(
        'Cannot generate PDF: critically low disk space. '
        'Please free up at least 100 MB.',
      );
    }

    final applyWatermark = await shouldApplyWatermark(school);
    // Compute contentHash from stored field, falling back to sha256 of content
    final contentHash = lesson.contentHash ??
        sha256.convert(utf8.encode(lesson.content)).toString();

    final cacheKey = PdfCacheKey(
      contentHash: contentHash,
      applyWatermark: applyWatermark,
      schoolNameHash: sha256.convert(utf8.encode(school.schoolName)).toString(),
      logoHash: school.logoUrl != null
          ? sha256.convert(utf8.encode(school.logoUrl!)).toString()
          : null,
    );

    // Check cache
    final cached = await _db.pdfCacheDao.get(cacheKey.compositeKey);
    if (cached != null) return cached;

    // Generate in isolate
    // lesson.topic is used as the PDF title — the schema uses `topic`
    // to represent the lesson title, not a separate `title` column.
    final params = _PdfParams(
      lessonTitle: lesson.topic,
      lessonContent: lesson.content,
      schoolName: school.schoolName,
      applyWatermark: applyWatermark,
      teacherEmail: teacherEmail,
      references: await _buildLessonReferences(lesson),
    );

    final pdfBytes = await Isolate.run(() => _generatePdfInIsolate(params));

    // Audit log the PDF export
    await logPdfExport(
      teacherId: teacherId,
      schoolId: school.serverId,
      topic: lesson.topic,
    );

    // Cache result
    await _db.pdfCacheDao.insert(
      cacheKey.compositeKey,
      pdfBytes,
      DateTime.now(),
    );

    return pdfBytes;
  }

  /// Collects the lesson's source references for the PDF References section:
  /// the linked scheme-of-work reference (if any) plus the stored
  /// AI-generated / teacher-entered references from the lesson content JSON.
  /// Every entry is a {text, origin} map with origin 'scheme' | 'teacher' |
  /// 'ai'. Malformed or missing content never throws.
  Future<List<Map<String, dynamic>>> _buildLessonReferences(
      Lesson lesson) async {
    final references = <Map<String, dynamic>>[];

    // Priority 1: linked scheme of work ("From scheme of work").
    final schemeId = int.tryParse(lesson.schemeOfWorkId ?? '');
    if (schemeId != null) {
      try {
        final scheme = await _db.schemeOfWorkDao.getById(schemeId);
        if (scheme != null) {
          final topic = scheme.adminEditedTopic ?? scheme.topic;
          final base = '${lesson.subject} Scheme of Work — Week ${lesson.week}';
          final text =
              topic.trim().isNotEmpty ? '$base: ${topic.trim()}' : base;
          references.add({'text': text, 'origin': 'scheme'});
        }
      } catch (_) {
        // Scheme missing — continue with the stored references only.
      }
    }

    // Priority 2: references stored inside the lesson content JSON.
    try {
      final content = jsonDecode(lesson.content);
      if (content is Map<String, dynamic>) {
        final stored = content['references'];
        if (stored is List) {
          for (final entry in stored) {
            if (entry is! Map) continue;
            final map = Map<String, dynamic>.from(entry);
            final text =
                (map['text'] ?? map['title'] ?? '').toString().trim();
            if (text.isEmpty) continue;
            var origin = map['origin']?.toString().trim().toLowerCase();
            if (origin != 'teacher' && origin != 'ai') {
              origin = 'ai';
            }
            references.add({'text': text, 'origin': origin});
          }
        }
      }
    } catch (_) {
      // Content may be encrypted or malformed; references are skipped.
    }

    return references;
  }
}

/// Human-readable origin label for a reference in the PDF.
String _pdfOriginLabel(String origin) {
  switch (origin) {
    case 'scheme':
      return 'From scheme of work';
    case 'teacher':
      return 'Teacher entered';
    default:
      return 'AI-generated';
  }
}

// Separate function for isolate entry point
class _PdfParams {
  final String lessonTitle;
  final String lessonContent;
  final String schoolName;
  final bool applyWatermark;
  final String? teacherEmail;

  /// {text, origin} entries for the References section; empty when none.
  final List<Map<String, dynamic>> references;

  _PdfParams({
    required this.lessonTitle,
    required this.lessonContent,
    required this.schoolName,
    required this.applyWatermark,
    this.teacherEmail,
    this.references = const [],
  });
}

Future<Uint8List> _generatePdfInIsolate(_PdfParams params) async {
  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) {
        final widgets = <pw.Widget>[];

        // Watermark behind content (if applicable)
        if (params.applyWatermark) {
          final watermarkText = params.teacherEmail != null
              ? 'Generated by ClassAI — ${params.schoolName} — ${params.teacherEmail}'
              : 'Generated by ClassAI — ${params.schoolName}';
          widgets.add(
            pw.Center(
              child: pw.Opacity(
                opacity: 0.1,
                child: pw.Transform.rotate(
                  angle: -0.4,
                  child: pw.Text(
                    watermarkText,
                    style: pw.TextStyle(
                      fontSize: 48,
                      color: PdfColors.grey400,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        widgets.addAll([
          pw.Header(text: params.lessonTitle),
          pw.Paragraph(text: params.lessonContent),
        ]);

        // ── References section ────────────────────────────────
        widgets.add(pw.SizedBox(height: 16));
        widgets.add(pw.Text(
          'References',
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ));
        widgets.add(pw.SizedBox(height: 8));
        if (params.references.isEmpty) {
          widgets.add(pw.Paragraph(
            text: 'No source references provided.',
            style: pw.TextStyle(
              fontSize: 11,
              color: PdfColors.grey600,
              fontStyle: pw.FontStyle.italic,
            ),
          ));
        } else {
          for (final ref in params.references) {
            final text = (ref['text'] ?? '').toString();
            final label =
                _pdfOriginLabel(ref['origin']?.toString() ?? 'ai');
            widgets.add(pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.RichText(
                text: pw.TextSpan(
                  style: const pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.grey800,
                  ),
                  children: [
                    pw.TextSpan(text: '• $text '),
                    pw.TextSpan(
                      text: '($label)',
                      style: pw.TextStyle(
                        fontStyle: pw.FontStyle.italic,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
              ),
            ));
          }
        }

        return widgets;
      },
    ),
  );

  final savedBytes = await doc.save();
  return Uint8List.fromList(savedBytes);
}
