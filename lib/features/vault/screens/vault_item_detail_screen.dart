// lib/features/vault/screens/vault_item_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/credit_service.dart';
import 'package:classai/main.dart' show databaseProvider;
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';

/// Detail view for a single vault item.
///
/// Shows full content, author, tier badge, credit cost, and an
/// "Acquire for X credits" button. If already acquired, shows
/// the acquisition date instead.
class VaultItemDetailScreen extends ConsumerWidget {
  final VaultItem item;

  const VaultItemDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final creditData = ref.watch(creditStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(item.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Thumbnail
          if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty)
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  item.thumbnailUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.image, size: 64),
                ),
              ),
            ),
          if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty)
            const SizedBox(height: 16),

          // Title
          Text(
            item.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Author + Tier badge
          Row(
            children: [
              Text(
                'By ${item.authorName}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              _TierBadge(tier: item.minTier),
            ],
          ),
          const SizedBox(height: 8),

          // Subject/Class/Curriculum chips
          Wrap(
            spacing: 8,
            children: [
              Chip(
                label: Text(item.subject, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
              ),
              Chip(
                label: Text(item.classLevel,
                    style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
              ),
              if (item.curriculum.isNotEmpty)
                Chip(
                  label: Text(item.curriculum,
                      style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Description
          if (item.description.isNotEmpty) ...[
            Text(
              'Description',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.description,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
          ],

          // Content preview
          Text(
            'Content',
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
              item.content,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),

          // Credit cost
          Row(
            children: [
              const Icon(Icons.monetization_on, size: 20, color: Colors.amber),
              const SizedBox(width: 4),
              Text(
                '${item.creditCost} credits',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade800,
                ),
              ),
            ],
          ),

          if (item.acquisitionDate != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.check_circle, size: 20, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  'Acquired on ${_formatDate(item.acquisitionDate!)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 24),

          // Acquire button
          if (item.acquisitionDate == null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _acquireItem(context, ref, item),
                icon: const Icon(Icons.shopping_cart),
                label: Text('Acquire for ${item.creditCost} credits'),
              ),
            ),

          if (creditData.currentCredits < item.creditCost)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'You have ${creditData.currentCredits} credits. '
                'Purchase more to acquire this item.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _acquireItem(
      BuildContext context, WidgetRef ref, VaultItem item) async {
    final creditData = ref.read(creditStateProvider);
    if (creditData.currentCredits < item.creditCost) {
      if (!context.mounted) return;
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Insufficient Credits'),
          content: Text(
            'This item costs ${item.creditCost} credits, but you only have '
            '${creditData.currentCredits}. Would you like to purchase more?',
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
      if (result == true && context.mounted) {
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

    if (confirmed == true && context.mounted) {
      try {
        final db = ref.read(databaseProvider);
        final creditService = CreditService(db);
        final batchId = await creditService.spendCredits(
          amount: item.creditCost,
          contentIds: ['vault_item:${item.id}'],
        );

        // Mark item as acquired
        await db.vaultItemsDao.markAcquired(item.id, creditSpentBatchId: batchId);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${item.title}" acquired!')),
          );
          await ref.read(creditStateProvider.notifier).refresh();
          Navigator.of(context).pop(); // Go back to vault browser
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to acquire item: $e')),
          );
        }
      }
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// Badge displaying the minimum tier required for an item.
class _TierBadge extends StatelessWidget {
  final String tier;

  const _TierBadge({required this.tier});

  @override
  Widget build(BuildContext context) {
    final (Color bgColor, Color fgColor, String label) = switch (tier) {
      'free' => (Colors.grey.shade200, Colors.grey.shade700, 'Free'),
      'basic' => (Colors.blue.shade100, Colors.blue.shade700, 'Basic'),
      'standard' => (Colors.amber.shade100, Colors.amber.shade900, 'Standard'),
      'elite' => (Colors.purple.shade100, Colors.purple.shade700, 'Elite'),
      _ => (Colors.grey.shade200, Colors.grey.shade700, tier),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: fgColor,
        ),
      ),
    );
  }
}
