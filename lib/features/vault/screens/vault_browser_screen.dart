// lib/features/vault/screens/vault_browser_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/main.dart' show databaseProvider;
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';

/// Vault browser screen showing approved items in a searchable grid.
///
/// Teachers can browse, filter, and acquire vault items using credits.
class VaultBrowserScreen extends ConsumerStatefulWidget {
  const VaultBrowserScreen({super.key});

  @override
  ConsumerState<VaultBrowserScreen> createState() => _VaultBrowserScreenState();
}

class _VaultBrowserScreenState extends ConsumerState<VaultBrowserScreen> {
  List<VaultItem> _items = [];
  bool _loading = true;
  String? _errorMessage;

  // Filter state
  String? _filterSubject;
  String? _filterClassLevel;
  String? _filterCurriculum;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      final dao = ref.read(databaseProvider).vaultItemsDao;
      final items = await dao.filter(
        subject: _filterSubject,
        classLevel: _filterClassLevel,
        curriculum: _filterCurriculum,
      );
      setState(() {
        _items = items;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load vault items: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _acquireItem(VaultItem item) async {
    final creditData = ref.read(creditStateProvider);
    if (creditData.currentCredits < item.creditCost) {
      if (!mounted) return;
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Insufficient Credits'),
          content: Text(
            'This item costs ${item.creditCost} credits, but you only have '
            '${creditData.currentCredits}. Would you like to purchase more credits?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Get Credits'),
            ),
          ],
        ),
      );
      if (result == true && mounted) {
        context.push('/payment');
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Acquire "${item.title}"'),
        content: Text(
          'This will cost ${item.creditCost} credit(s). '
          'Do you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Acquire'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final dao = ref.read(databaseProvider).vaultItemsDao;
        final batchId = DateTime.now().millisecondsSinceEpoch.toString();
        await dao.markAcquired(item.id, creditSpentBatchId: batchId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${item.title}" acquired!')),
          );
          await ref.read(creditStateProvider.notifier).refresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to acquire item: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final creditData = ref.watch(creditStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '🔓 ${creditData.currentCredits} credits',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Publish new item',
            onPressed: () => context.push('/vault/publish'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter bar
          _FilterBar(
            onApply: (subject, classLevel, curriculum) {
              setState(() {
                _filterSubject = subject;
                _filterClassLevel = classLevel;
                _filterCurriculum = curriculum;
              });
              _loadItems();
            },
          ),
          // Items grid
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _errorMessage!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _loadItems,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _items.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inventory_2_outlined,
                                    size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                Text(
                                  'No vault items found',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Adjust filters or check back later.',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.75,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: _items.length,
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              return _VaultItemCard(
                                item: item,
                                onTap: () => _acquireItem(item),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter Bar
// ---------------------------------------------------------------------------

class _FilterBar extends StatefulWidget {
  final void Function(String? subject, String? classLevel, String? curriculum)
      onApply;

  const _FilterBar({required this.onApply});

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  final _subjectCtrl = TextEditingController();
  final _classLevelCtrl = TextEditingController();
  final _curriculumCtrl = TextEditingController();

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _classLevelCtrl.dispose();
    _curriculumCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _subjectCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Subject',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _classLevelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Class Level',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _curriculumCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Curriculum',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      _subjectCtrl.clear();
                      _classLevelCtrl.clear();
                      _curriculumCtrl.clear();
                      widget.onApply(null, null, null);
                    },
                    child: const Text('Clear'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      widget.onApply(
                        _subjectCtrl.text.isNotEmpty
                            ? _subjectCtrl.text
                            : null,
                        _classLevelCtrl.text.isNotEmpty
                            ? _classLevelCtrl.text
                            : null,
                        _curriculumCtrl.text.isNotEmpty
                            ? _curriculumCtrl.text
                            : null,
                      );
                    },
                    child: const Text('Filter'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vault Item Card
// ---------------------------------------------------------------------------

class _VaultItemCard extends StatelessWidget {
  final VaultItem item;
  final VoidCallback onTap;

  const _VaultItemCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail placeholder
              Container(
                height: 80,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          item.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.image,
                            size: 40,
                          ),
                        ),
                      )
                    : const Icon(Icons.image, size: 40),
              ),
              const SizedBox(height: 8),
              // Title
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              // Metadata
              Text(
                '${item.subject} • ${item.classLevel}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              // Credit cost
              Row(
                children: [
                  Icon(Icons.monetization_on, size: 16, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(
                    '${item.creditCost} credits',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.lock_outline,
                    size: 14,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
