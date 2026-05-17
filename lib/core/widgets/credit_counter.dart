import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';

/// Credit counter chip in the AppBar.
///
/// Renders an [ActionChip] showing the current credit count. On tap, shows
/// an [AlertDialog] with tier, next refill time, and an upgrade action.
class CreditCounter extends ConsumerWidget {
  const CreditCounter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditData = ref.watch(creditStateProvider);
    final theme = Theme.of(context);

    return ActionChip(
      avatar: Text(
        '🔓',
        style: theme.textTheme.bodyMedium,
      ),
      label: Text(
        creditData.loading ? '…' : '${creditData.currentCredits}',
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      onPressed: () => _showCreditDetailsDialog(context, creditData),
    );
  }

  void _showCreditDetailsDialog(BuildContext context, CreditStateData data) {
    showDialog(
      context: context,
      builder: (_) => _CreditDetailsDialog(data: data),
    );
  }
}

class _CreditDetailsDialog extends StatelessWidget {
  final CreditStateData data;

  const _CreditDetailsDialog({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM d, yyyy – h:mm a');

    return AlertDialog(
      title: const Text('Credits'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current credits
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Available credits',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                '🔓 ${data.currentCredits}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Tier name
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tier',
                style: theme.textTheme.bodyMedium,
              ),
              Chip(
                label: Text(
                  data.tierName,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Next refill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Next refill',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                data.nextRefillTime != null
                    ? dateFormat.format(data.nextRefillTime!)
                    : 'N/A',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          if (data.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              data.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            context.push('/payment');
          },
          child: const Text('Upgrade'),
        ),
      ],
    );
  }
}
