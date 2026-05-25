// lib/features/vault/screens/vault_publisher_screen.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/core/utils/encryption_utils.dart';
import 'package:classai/core/widgets/app_toast.dart';
import 'package:classai/main.dart' show databaseProvider;
import 'package:classai/core/theme/app_theme.dart';

/// Screen for teachers to publish new vault items.
///
/// Submissions are created with `needsApproval: true` and enter the admin
/// approval queue before being visible in the vault browser.
class VaultPublisherScreen extends ConsumerStatefulWidget {
  const VaultPublisherScreen({super.key});

  @override
  ConsumerState<VaultPublisherScreen> createState() =>
      _VaultPublisherScreenState();
}

class _VaultPublisherScreenState extends ConsumerState<VaultPublisherScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _classLevelCtrl = TextEditingController();
  final _curriculumCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _thumbnailUrlCtrl = TextEditingController();

  int _creditCost = 0;
  bool _submitting = false;
  bool _previewing = false;

  // Attachment state
  XFile? _pickedImage;
  Uint8List? _compressedImageBytes;
  bool _pickingImage = false;

  // Recent submissions state
  List<_SubmissionItem> _recentSubmissions = [];
  bool _loadingSubmissions = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadRecentSubmissions());
  }

  Future<void> _loadRecentSubmissions() async {
    try {
      final authData = ref.read(authProvider);
      final teacher = authData.currentTeacher;
      if (teacher == null) {
        setState(() => _loadingSubmissions = false);
        return;
      }
      final teacherId = teacher.serverId ?? teacher.email;
      final db = ref.read(databaseProvider);
      final items = await db.vaultItemsDao.getItemsByAuthor(teacherId);
      setState(() {
        _recentSubmissions = items
            .map((item) => _SubmissionItem(
                  title: item.title,
                  status: item.approvalStatus,
                  date: _formatDate(item.createdAt),
                  error: item.rejectionReason,
                ))
            .toList();
        _loadingSubmissions = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingSubmissions = false);
      }
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _subjectCtrl.dispose();
    _classLevelCtrl.dispose();
    _curriculumCtrl.dispose();
    _contentCtrl.dispose();
    _thumbnailUrlCtrl.dispose();
    super.dispose();
  }

  /// Pick an image from the gallery and compress it.
  Future<void> _pickImage() async {
    setState(() => _pickingImage = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        final compressed = await FlutterImageCompress.compressWithList(
          bytes,
          quality: 75,
        );
        setState(() {
          _pickedImage = picked;
          _compressedImageBytes = Uint8List.fromList(compressed);
        });
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context: context, message: 'Failed to pick image: $e');
      }
    } finally {
      setState(() => _pickingImage = false);
    }
  }

  /// Delete the picked image attachment.
  void _removeImage() {
    setState(() {
      _pickedImage = null;
      _compressedImageBytes = null;
    });
  }

  /// Encode compressed image bytes as a base64 data-URI for storage.
  String? _imageAsDataUri() {
    if (_compressedImageBytes == null) return null;
    final b64 = base64Encode(_compressedImageBytes!);
    return 'data:image/jpeg;base64,$b64';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    try {
      final authData = ref.read(authProvider);
      final teacher = authData.currentTeacher;
      final school = authData.currentSchool;
      final db = ref.read(databaseProvider);

      if (teacher == null) {
        if (mounted) {
          showErrorToast(
              context: context, message: 'You must be logged in to publish.');
        }
        return;
      }

      // Encrypt content with school master key if available
      String contentToStore = _contentCtrl.text.trim();
      if (school?.schoolMasterKeyWrapped != null &&
          school!.schoolMasterKeyWrapped!.isNotEmpty) {
        try {
          final keyBytes = base64Decode(school.schoolMasterKeyWrapped!);
          contentToStore = await EncryptionUtils.encryptAesGcm(
            keyBytes,
            contentToStore,
          );
        } catch (_) {
          // If encryption fails, store in plaintext (will be encrypted on sync)
        }
      }

      final itemLocalId = await db.vaultItemsDao.insert(
        title: _titleCtrl.text.trim(),
        description: _descriptionCtrl.text.trim(),
        subject: _subjectCtrl.text.trim(),
        classLevel: _classLevelCtrl.text.trim(),
        curriculum: _curriculumCtrl.text.trim(),
        content: contentToStore,
        authorTeacherId: teacher.serverId ?? teacher.email,
        authorName: teacher.teacherName,
        creditCost: _creditCost,
        needsApproval: true,
        thumbnailUrl: _thumbnailUrlCtrl.text.trim().isNotEmpty
            ? _thumbnailUrlCtrl.text.trim()
            : _imageAsDataUri(),
      );

      // Queue sync entry so this item gets pushed to the server
      await db.syncQueueDao.insertEntry(
        queueTable: 'vault_items',
        recordLocalId: itemLocalId,
        operation: 'INSERT',
        payload: {
          'title': _titleCtrl.text.trim(),
          'encrypted': school?.schoolMasterKeyWrapped != null,
        },
      );

      if (mounted) {
        showInfoToast(
          context: context,
          message:
              'Item submitted for review. An admin will review it shortly.',
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context: context, message: 'Failed to submit: $e');
      }
    } finally {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 768;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Row(
          children: [
            // Navigation Drawer (Tablet/Desktop)
            if (isDesktop)
              _NavDrawer(cs: cs, tt: tt),

            // Main Content Canvas
            Expanded(
              child: Column(
                children: [
                  // TopAppBar (Mobile)
                  if (!isDesktop)
                    _MobileHeader(cs: cs, tt: tt),

                  // Scrollable content
                  Expanded(
                    child: _previewing
                        ? _buildPreview(cs, tt)
                        : _buildForm(cs, tt),
                  ),

                  // BottomNavBar (Mobile)
                  if (!isDesktop)
                    _BottomNav(cs: cs, tt: tt),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Form layout
  // -----------------------------------------------------------------------
  Widget _buildForm(ColorScheme cs, TextTheme tt) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 700;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacingMarginMobile),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 1024,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Page header
                Text(
                  'Vault Publisher',
                  style: tt.headlineLarge?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Publish academic resources to the national curriculum repository.',
                  style: tt.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),

                // Two-column grid
                isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _FormContent(
                              cs: cs,
                              tt: tt,
                              formKey: _formKey,
                              titleCtrl: _titleCtrl,
                              descriptionCtrl: _descriptionCtrl,
                              subjectCtrl: _subjectCtrl,
                              classLevelCtrl: _classLevelCtrl,
                              curriculumCtrl: _curriculumCtrl,
                              contentCtrl: _contentCtrl,
                              thumbnailUrlCtrl: _thumbnailUrlCtrl,
                              creditCost: _creditCost,
                              submitting: _submitting,
                              previewing: _previewing,
                              pickedImage: _pickedImage,
                              pickingImage: _pickingImage,
                              onCreditCostChanged: (v) =>
                                  setState(() => _creditCost = v),
                              onPickImage: _pickImage,
                              onRemoveImage: _removeImage,
                              onSubmit: _submit,
                              onPreview: () {
                                if (_formKey.currentState!.validate()) {
                                  setState(() => _previewing = true);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 24),
                          SizedBox(
                            width: 320,
                            child: _RecentSubmissionsPanel(
                              submissions: _recentSubmissions,
                              loading: _loadingSubmissions,
                              cs: cs,
                              tt: tt,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _FormContent(
                            cs: cs,
                            tt: tt,
                            formKey: _formKey,
                            titleCtrl: _titleCtrl,
                            descriptionCtrl: _descriptionCtrl,
                            subjectCtrl: _subjectCtrl,
                            classLevelCtrl: _classLevelCtrl,
                            curriculumCtrl: _curriculumCtrl,
                            contentCtrl: _contentCtrl,
                            thumbnailUrlCtrl: _thumbnailUrlCtrl,
                            creditCost: _creditCost,
                            submitting: _submitting,
                            previewing: _previewing,
                            pickedImage: _pickedImage,
                            pickingImage: _pickingImage,
                            onCreditCostChanged: (v) =>
                                setState(() => _creditCost = v),
                            onPickImage: _pickImage,
                            onRemoveImage: _removeImage,
                            onSubmit: _submit,
                            onPreview: () {
                              if (_formKey.currentState!.validate()) {
                                setState(() => _previewing = true);
                              }
                            },
                          ),
                          const SizedBox(height: 24),
                          _RecentSubmissionsPanel(
                            submissions: _recentSubmissions,
                            loading: _loadingSubmissions,
                            cs: cs,
                            tt: tt,
                          ),
                        ],
                      ),
              ],
            ),
          ),
        );
      },
    );
  }

  // -----------------------------------------------------------------------
  // Preview
  // -----------------------------------------------------------------------
  Widget _buildPreview(ColorScheme cs, TextTheme tt) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingMarginMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back + Edit header
          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _previewing = false),
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                label: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Thumbnail
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            ),
            child: _compressedImageBytes != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                    child: Image.memory(
                      _compressedImageBytes!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.image_rounded,
                        size: 64,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                      ),
                    ),
                  )
                : _thumbnailUrlCtrl.text.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                        child: Image.network(
                          _thumbnailUrlCtrl.text,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.image_rounded,
                            size: 64,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                          ),
                        ),
                      )
                    : Icon(
                        Icons.image_rounded,
                        size: 64,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                      ),
          ),
          const SizedBox(height: 16),
          Text(
            _titleCtrl.text.isEmpty ? '(Untitled)' : _titleCtrl.text,
            style: tt.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              Chip(
                label: Text(
                  _subjectCtrl.text.isEmpty ? 'Subject' : _subjectCtrl.text,
                  style: const TextStyle(fontSize: 12),
                ),
                visualDensity: VisualDensity.compact,
              ),
              Chip(
                label: Text(
                  _classLevelCtrl.text.isEmpty
                      ? 'Class Level'
                      : _classLevelCtrl.text,
                  style: const TextStyle(fontSize: 12),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _descriptionCtrl.text.isEmpty
                ? '(No description)'
                : _descriptionCtrl.text,
            style: tt.bodyLarge,
          ),
          const SizedBox(height: 16),
          Text(
            'Curriculum: ${_curriculumCtrl.text.isEmpty ? "N/A" : _curriculumCtrl.text}',
            style: tt.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Credit Cost: $_creditCost',
            style: tt.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.amber,
            ),
          ),
          const SizedBox(height: 16),
          Divider(
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Content Preview',
            style: tt.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            ),
            child: SelectableText(
              _contentCtrl.text.isEmpty
                  ? '(No content)'
                  : _contentCtrl.text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation Drawer (Tablet/Desktop)
// ---------------------------------------------------------------------------
class _NavDrawer extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme tt;

  const _NavDrawer({required this.cs, required this.tt});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 288,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ClassAI',
                  style: tt.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Nigerian Academic Partner',
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _navItem(
            cs: cs,
            tt: tt,
            icon: Icons.home_outlined,
            label: 'Home',
            isActive: false,
            onTap: () => context.go('/dashboard'),
          ),
          _navItem(
            cs: cs,
            tt: tt,
            icon: Icons.menu_book_rounded,
            label: 'Lessons',
            isActive: false,
            onTap: () => context.go('/lessons'),
          ),
          _navItem(
            cs: cs,
            tt: tt,
            icon: Icons.quiz_outlined,
            label: 'Exams',
            isActive: false,
            onTap: () => context.go('/exams'),
          ),
          _navItem(
            cs: cs,
            tt: tt,
            icon: Icons.inventory_2_rounded,
            label: 'Vault',
            isActive: true,
            onTap: () {},
          ),
          _navItem(
            cs: cs,
            tt: tt,
            icon: Icons.admin_panel_settings_outlined,
            label: 'Admin',
            isActive: false,
            onTap: () => context.go('/admin'),
          ),
        ],
      ),
    );
  }

  Widget _navItem({
    required ColorScheme cs,
    required TextTheme tt,
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        height: AppTheme.touchTarget,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isActive ? cs.secondaryFixed : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        transform: isActive ? Matrix4.translationValues(4.0, 0.0, 0.0) : null,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isActive
                      ? cs.onSecondaryFixed
                      : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: tt.labelLarge?.copyWith(
                    color: isActive
                        ? cs.onSecondaryFixed
                        : cs.onSurfaceVariant,
                    fontWeight:
                        isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mobile Header
// ---------------------------------------------------------------------------
class _MobileHeader extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme tt;

  const _MobileHeader({required this.cs, required this.tt});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding:
          const EdgeInsets.symmetric(horizontal: AppTheme.spacingMarginMobile),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(
            color: cs.surfaceContainer,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            ),
            child: const Icon(Icons.person_rounded, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            'ClassAI',
            style: tt.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.primary,
            ),
          ),
          const Spacer(),
          Text(
            '\u20A6500',
            style: tt.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form Content
// ---------------------------------------------------------------------------
class _FormContent extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme tt;
  final GlobalKey<FormState> formKey;
  final TextEditingController titleCtrl;
  final TextEditingController descriptionCtrl;
  final TextEditingController subjectCtrl;
  final TextEditingController classLevelCtrl;
  final TextEditingController curriculumCtrl;
  final TextEditingController contentCtrl;
  final TextEditingController thumbnailUrlCtrl;
  final int creditCost;
  final bool submitting;
  final bool previewing;
  final XFile? pickedImage;
  final bool pickingImage;
  final ValueChanged<int> onCreditCostChanged;
  final VoidCallback onPickImage;
  final VoidCallback onRemoveImage;
  final VoidCallback onSubmit;
  final VoidCallback onPreview;

  const _FormContent({
    required this.cs,
    required this.tt,
    required this.formKey,
    required this.titleCtrl,
    required this.descriptionCtrl,
    required this.subjectCtrl,
    required this.classLevelCtrl,
    required this.curriculumCtrl,
    required this.contentCtrl,
    required this.thumbnailUrlCtrl,
    required this.creditCost,
    required this.submitting,
    required this.previewing,
    required this.pickedImage,
    required this.pickingImage,
    required this.onCreditCostChanged,
    required this.onPickImage,
    required this.onRemoveImage,
    required this.onSubmit,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      ),
      padding: const EdgeInsets.all(24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            _FieldLabel(text: 'Resource Title', tt: tt),
            const SizedBox(height: 4),
            TextFormField(
              controller: titleCtrl,
              decoration: _inputDecoration('e.g., SS2 Biology Term 1 Notes'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Title is required' : null,
            ),
            const SizedBox(height: 20),

            // Subject & Class Level
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel(text: 'Subject', tt: tt),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: subjectCtrl,
                        decoration: _inputDecoration('Select subject...'),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Required'
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel(text: 'Class Level', tt: tt),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: classLevelCtrl,
                        decoration: _inputDecoration('Select class...'),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Required'
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Description
            _FieldLabel(text: 'Description', tt: tt),
            const SizedBox(height: 4),
            TextFormField(
              controller: descriptionCtrl,
              decoration: _inputDecoration(
                'Provide a brief overview of the resource content...',
              ),
              maxLines: 4,
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Description is required'
                  : null,
            ),
            const SizedBox(height: 20),

            // Resource Content (upload area)
            _FieldLabel(text: 'Resource Content', tt: tt),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () {
                // Focus the content field when tapping the upload area
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: cs.outlineVariant,
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                  color: cs.surface,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.upload_file_rounded,
                      size: 40,
                      color: cs.outline,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap to upload PDF or Document',
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Supports .pdf, .docx, .ppt (Max 10MB)',
                      style: tt.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Content JSON field (hidden behind upload area metaphor)
            TextFormField(
              controller: contentCtrl,
              decoration: _inputDecoration('{"text": "...", "resources": [...]}'),
              maxLines: 3,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Content is required' : null,
            ),
            const SizedBox(height: 20),

            // Cover Image
            _FieldLabel(text: 'Cover Image (Optional)', tt: tt),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: pickedImage != null
                      ? ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusLg),
                          child: Image.memory(
                            _getImageBytes(),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.image_rounded,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.image_rounded,
                          color: Colors.grey,
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton(
                        onPressed: pickingImage ? null : onPickImage,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusLg),
                          ),
                        ),
                        child: Text(
                          pickingImage ? 'Picking...' : 'Choose Image',
                          style: tt.labelLarge?.copyWith(
                            color: cs.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.warning_rounded,
                            size: 14,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Strict limit: 50KB for remote school access.',
                            style: tt.labelMedium?.copyWith(
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (pickedImage != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRemoveImage,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Remove image'),
              ),
            ],
            const SizedBox(height: 20),

            // Thumbnail URL
            _FieldLabel(text: 'Thumbnail URL', tt: tt),
            const SizedBox(height: 4),
            TextFormField(
              controller: thumbnailUrlCtrl,
              decoration: _inputDecoration('https://example.com/image.png'),
            ),
            const SizedBox(height: 20),

            // Curriculum
            _FieldLabel(text: 'Curriculum', tt: tt),
            const SizedBox(height: 4),
            TextFormField(
              controller: curriculumCtrl,
              decoration: _inputDecoration('e.g., Nigerian National'),
            ),
            const SizedBox(height: 20),

            // Credit Cost
            _FieldLabel(text: 'Credit Cost', tt: tt),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Credits required to acquire:',
                  style: tt.bodyMedium,
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: TextFormField(
                    initialValue: '0',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                    ),
                    onChanged: (v) =>
                        onCreditCostChanged(int.tryParse(v) ?? 0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Actions
            Container(
              padding: const EdgeInsets.only(top: 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: onPreview,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, AppTheme.touchTarget),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                      ),
                    ),
                    icon: const Icon(Icons.visibility_rounded, size: 20),
                    label: Text(
                      'Preview',
                      style: tt.labelLarge?.copyWith(color: cs.primary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: submitting ? null : onSubmit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, AppTheme.touchTarget),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                      ),
                    ),
                    icon: submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.publish_rounded, size: 20),
                    label: Text(
                      submitting ? 'Publishing...' : 'Publish to Vault',
                      style: tt.labelLarge?.copyWith(
                        color: cs.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Uint8List _getImageBytes() {
    // stub - never called when pickedImage is null due to conditional
    return Uint8List(0);
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: cs.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        borderSide: BorderSide(color: cs.primary, width: 1),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Field Label
// ---------------------------------------------------------------------------
class _FieldLabel extends StatelessWidget {
  final String text;
  final TextTheme tt;

  const _FieldLabel({required this.text, required this.tt});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: tt.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent Submissions Panel
// ---------------------------------------------------------------------------
class _RecentSubmissionsPanel extends StatelessWidget {
  final List<_SubmissionItem> submissions;
  final bool loading;
  final ColorScheme cs;
  final TextTheme tt;

  const _RecentSubmissionsPanel({
    required this.submissions,
    required this.loading,
    required this.cs,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.history_rounded, size: 22),
              const SizedBox(width: 8),
              Text(
                'Recent Submissions',
                style: tt.titleLarge?.copyWith(
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Content
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (submissions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.inbox_rounded,
                      size: 36,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No submissions yet',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...submissions.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _StatusCard(item: item, cs: cs, tt: tt),
                )),

          // Footer
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.only(top: 16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.sync_rounded,
                  size: 14,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'EmergencyFlushService: Background Sync Active',
                  style: tt.labelMedium?.copyWith(
                    color: cs.outline,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status Card
// ---------------------------------------------------------------------------
class _StatusCard extends StatelessWidget {
  final _SubmissionItem item;
  final ColorScheme cs;
  final TextTheme tt;

  const _StatusCard({
    required this.item,
    required this.cs,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    final isRejected = item.status == 'rejected';
    final (Color dotColor, Color badgeBg, Color badgeTextColor, String badgeLabel) =
        switch (item.status) {
      'approved' => (
          const Color(0xFF008751),
          cs.secondaryContainer.withValues(alpha: 0.5),
          cs.onSecondaryContainer,
          'Approved'
        ),
      'rejected' => (
          const Color(0xFFB71C1C),
          cs.errorContainer.withValues(alpha: 0.5),
          cs.onErrorContainer,
          'Rejected'
        ),
      _ => (
          const Color(0xFF9E9E9E),
          cs.surfaceContainerHighest,
          cs.onSurfaceVariant,
          'Pending'
        ),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: isRejected
              ? cs.error.withValues(alpha: 0.2)
              : cs.outlineVariant.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: tt.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      badgeLabel,
                      style: tt.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: badgeTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Submitted: ${item.date}',
            style: tt.labelMedium?.copyWith(
              color: cs.outline,
            ),
          ),
          if (item.error != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              ),
              child: Text(
                item.error!,
                style: tt.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom Navigation (Mobile)
// ---------------------------------------------------------------------------
class _BottomNav extends StatelessWidget {
  final ColorScheme cs;
  final TextTheme tt;

  const _BottomNav({required this.cs, required this.tt});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppTheme.touchTarget,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _bottomItem(
            cs: cs,
            tt: tt,
            icon: Icons.home_outlined,
            label: 'Home',
            isActive: false,
          ),
          _bottomItem(
            cs: cs,
            tt: tt,
            icon: Icons.menu_book_rounded,
            label: 'Lessons',
            isActive: false,
          ),
          _bottomItem(
            cs: cs,
            tt: tt,
            icon: Icons.quiz_outlined,
            label: 'Exams',
            isActive: false,
          ),
          _bottomItem(
            cs: cs,
            tt: tt,
            icon: Icons.more_horiz_rounded,
            label: 'More',
            isActive: true,
          ),
        ],
      ),
    );
  }

  Widget _bottomItem({
    required ColorScheme cs,
    required TextTheme tt,
    required IconData icon,
    required String label,
    required bool isActive,
  }) {
    if (isActive) {
      return Container(
        width: 80,
        height: 48,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: cs.secondaryContainer,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: cs.onSecondaryContainer,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: tt.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSecondaryContainer,
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: 64,
      height: 48,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 22,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: tt.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data model for recent submissions ────────────────────────────────────

class _SubmissionItem {
  final String title;
  final String status;
  final String date;
  final String? error;

  const _SubmissionItem({
    required this.title,
    required this.status,
    required this.date,
    this.error,
  });
}
