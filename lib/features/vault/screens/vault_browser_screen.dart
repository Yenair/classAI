// lib/features/vault/screens/vault_browser_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/main.dart' show databaseProvider;
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/features/vault/screens/vault_item_detail_screen.dart';

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

  void _openDetail(VaultItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VaultItemDetailScreen(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault'),
        elevation: 0,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: cs.surface,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cs.primaryContainer.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_open_rounded,
                        size: 15, color: cs.onPrimaryContainer),
                    const SizedBox(width: 6),
                    Text(
                      '${ref.watch(creditStateProvider).currentCredits} credits',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onPrimaryContainer,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Publish new item',
            onPressed: () => context.push('/vault/publish'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Filter bar
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Subject',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Class Level',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Curriculum',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _filterSubject = null;
                            _filterClassLevel = null;
                            _filterCurriculum = null;
                          });
                          _loadItems();
                        },
                        child: const Text('Clear'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _filterSubject = _filterSubject;
                            _filterClassLevel = _filterClassLevel;
                            _filterCurriculum = _filterCurriculum;
                          });
                          _loadItems();
                        },
                        child: const Text('Filter'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Items grid
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                size: 56,
                                color: cs.error,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color: cs.error,
                                    ),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _loadItems,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _items.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.inventory_2_outlined,
                                  size: 64,
                                  color: cs.onSurfaceVariant
                                      .withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No vault items found',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Adjust filters or check back later.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
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
                                onTap: () => _openDetail(item),
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
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subjectCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Subject',
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
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
                      _subjectCtrl.text.isNotEmpty ? _subjectCtrl.text : null,
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

  /// Color per subscription tier
  Color _tierColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'free':
        return Colors.grey;
      case 'basic':
        return const Color(0xFF3674B5);
      case 'standard':
        return const Color(0xFF8C94FF);
      case 'elite':
        return const Color(0xFF5068D9);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
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
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: item.thumbnailUrl != null &&
                        item.thumbnailUrl!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          item.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.image_rounded,
                            size: 32,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                          ),
                        ),
                      )
                    : Icon(
                        Icons.image_rounded,
                        size: 32,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                      ),
              ),
              const SizedBox(height: 8),
              // Title
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 2),
              // Author
              Text(
                'By ${item.authorName}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Metadata
              Text(
                '${item.subject} \u00b7 ${item.classLevel}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Tier badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _tierColor(item.minTier).withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _tierColor(item.minTier).withValues(alpha: 0.35),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  item.minTier.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _tierColor(item.minTier),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const Spacer(),
              // Credit cost + lock
              Row(
                children: [
                  Icon(
                    Icons.monetization_on_rounded,
                    size: 14,
                    color: Colors.amber.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${item.creditCost} credits',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: cs.outline.withValues(alpha: 0.65),
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
