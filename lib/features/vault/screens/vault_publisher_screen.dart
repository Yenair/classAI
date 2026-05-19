// lib/features/vault/screens/vault_publisher_screen.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/core/utils/encryption_utils.dart';
import 'package:classai/main.dart' show databaseProvider;

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You must be logged in to publish.')),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Item submitted for review. An admin will review it shortly.',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit: $e')),
        );
      }
    } finally {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_previewing ? 'Preview' : 'Publish to Vault'),
        elevation: 0,
        actions: [
          if (!_previewing)
            TextButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  setState(() => _previewing = true);
                }
              },
              child: const Text('Preview'),
            ),
          if (_previewing)
            TextButton(
              onPressed: () => setState(() => _previewing = false),
              child: const Text('Edit'),
            ),
        ],
      ),
      body: _previewing ? _buildPreview() : _buildForm(),
    );
  }

  Widget _buildForm() {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Item Details',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Title *',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Title is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description *',
                  ),
                  maxLines: 3,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Description is required'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _subjectCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Subject *',
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _classLevelCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Class Level *',
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _curriculumCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Curriculum',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _contentCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Content (JSON) *',
                    hintText: '{"text": "...", "resources": [...]}',
                  ),
                  maxLines: 5,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Content is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _thumbnailUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Thumbnail URL',
                    hintText: 'https://example.com/image.png',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Attachment section
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attachment',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                if (_pickedImage != null)
                  Row(
                    children: [
                      Icon(
                        Icons.image_rounded,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _pickedImage!.name,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _removeImage,
                        tooltip: 'Remove image',
                      ),
                    ],
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _pickingImage ? null : _pickImage,
                    icon: _pickingImage
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.attach_file_rounded),
                    label:
                        Text(_pickingImage ? 'Picking\u2026' : 'Attach Image'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Credit Cost section
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Credit Cost',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Credits required to acquire:',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: TextFormField(
                        initialValue: '0',
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          isDense: true,
                        ),
                        onChanged: (v) =>
                            setState(() => _creditCost = int.tryParse(v) ?? 0),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit for Review'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Items require admin approval before appearing in the vault.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: _compressedImageBytes != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(16),
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
                        borderRadius: BorderRadius.circular(16),
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
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Chip(
                label: Text(
                  _subjectCtrl.text.isEmpty ? 'Subject' : _subjectCtrl.text,
                  style: const TextStyle(fontSize: 12),
                ),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
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
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          Text(
            'Curriculum: ${_curriculumCtrl.text.isEmpty ? "N/A" : _curriculumCtrl.text}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Credit Cost: $_creditCost',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              _contentCtrl.text.isEmpty ? '(No content)' : _contentCtrl.text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
