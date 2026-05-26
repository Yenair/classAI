import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';

/// Credit counter chip in the AppBar.
///
/// Stitch style: compact pill container, primary tint background when
/// credits are positive, thin mono-style numerics for the count.
class CreditCounter extends ConsumerWidget {
  const CreditCounter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditData = ref.watch(creditStateProvider);
    final cs = Theme.of(context).colorScheme;

    final hasError = creditData.errorMessage != null;
    final isPositive = !hasError && creditData.currentCredits > 0;
    final labelColor = hasError ? cs.error : (isPositive ? cs.primary : cs.error);

    return ActionChip(
      backgroundColor: labelColor.withValues(alpha: isPositive ? 0.10 : 0.12),
      side: BorderSide(
        color: labelColor.withValues(alpha: isPositive ? 0.24 : 0.30),
        width: 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      avatar: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: labelColor.withValues(alpha: isPositive ? 0.16 : 0.18),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Icon(
          hasError ? Icons.error_outline_rounded : Icons.lock_open_rounded,
          size: 11,
          color: labelColor,
        ),
      ),
      label: Text(
        hasError ? '—' : (creditData.loading ? '…' : '${creditData.currentCredits}'),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: labelColor,
              letterSpacing: 0.25,
            ),
      ),
      onPressed: () {
        if (creditData.currentCredits <= 0) {
          context.push('/insufficient-credit');
        } else {
          _showCreditDetailsDialog(context, creditData);
        }
      },
    );
  }

  void _showCreditDetailsDialog(BuildContext context, dynamic data) {
    showDialog(
      context: context,
      builder: (_) => _CreditDetailsDialog(data: data),
    );
  }
}

class _CreditDetailsDialog extends StatelessWidget {
  const _CreditDetailsDialog({required this.data});
  final dynamic data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('MMM d, yyyy – h:mm a');

    return AlertDialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: const BorderRadius.all(Radius.circular(10)),
            ),
            child: Icon(Icons.account_balance_rounded,
                color: cs.onPrimaryContainer, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            'Credits',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Available credits ──────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Available credits',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              Text(
                '${data.currentCredits}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                      letterSpacing: -0.25,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Tier ───────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tier',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              Chip(
                label: Text(
                  data.tierName,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimaryContainer,
                      ),
                ),
                backgroundColor: cs.primaryContainer,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Next refill ────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Next refill',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              Text(
                data.nextRefillTime != null
                    ? dateFormat.format(data.nextRefillTime!)
                    : 'N/A',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
          if (data.errorMessage != null) ...[
            const SizedBox(height: 14),
            Text(
              data.errorMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.error,
                    fontWeight: FontWeight.w500,
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
