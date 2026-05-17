// lib/features/vault/screens/vault_publisher_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    try {
      final authData = ref.read(authProvider);
      final teacher = authData.currentTeacher;
      final db = ref.read(databaseProvider);

      if (teacher == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You must be logged in to publish.')),
          );
        }
        return;
      }

      await db.vaultItemsDao.insert(
        title: _titleCtrl.text.trim(),
        description: _descriptionCtrl.text.trim(),
        subject: _subjectCtrl.text.trim(),
        classLevel: _classLevelCtrl.text.trim(),
        curriculum: _curriculumCtrl.text.trim(),
        content: _contentCtrl.text.trim(),
        authorTeacherId: teacher.serverId ?? teacher.email,
        authorName: teacher.teacherName,
        creditCost: _creditCost,
        needsApproval: true,
        thumbnailUrl: _thumbnailUrlCtrl.text.trim().isNotEmpty
            ? _thumbnailUrlCtrl.text.trim()
            : null,
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
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Item Details',
              style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Title *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Title is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionCtrl,
              decoration: const InputDecoration(
                labelText: 'Description *',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Description is required' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _subjectCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Subject *',
                      border: OutlineInputBorder(),
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
                      border: OutlineInputBorder(),
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
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contentCtrl,
              decoration: const InputDecoration(
                labelText: 'Content (JSON) *',
                border: OutlineInputBorder(),
                hintText: '{"text": "...", "resources": [...]}',
              ),
              maxLines: 5,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Content is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _thumbnailUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Thumbnail URL',
                border: OutlineInputBorder(),
                hintText: 'https://example.com/image.png',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Credit Cost',
              style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Credits required to acquire:'),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: TextFormField(
                    initialValue: '0',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        setState(() => _creditCost = int.tryParse(v) ?? 0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final theme = Theme.of(context);

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
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _thumbnailUrlCtrl.text.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      _thumbnailUrlCtrl.text,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.image,
                          size: 64),
                    ),
                  )
                : const Icon(Icons.image, size: 64),
          ),
          const SizedBox(height: 16),
          Text(
            _titleCtrl.text.isEmpty ? '(Untitled)' : _titleCtrl.text,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
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
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          Text(
            'Curriculum: ${_curriculumCtrl.text.isEmpty ? "N/A" : _curriculumCtrl.text}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Credit Cost: $_creditCost',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.amber.shade800,
            ),
          ),
          const SizedBox(height: 16),
          Divider(),
          const SizedBox(height: 8),
          Text(
            'Content Preview',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
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
