import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';

/// Daily credits counter chip in the AppBar.
///
/// Stitch style: compact pill container, primary tint background when
/// daily credits are positive, thin mono-style numerics for the count.
class DailyCreditsCounter extends ConsumerStatefulWidget {
  const DailyCreditsCounter({super.key, this.visible = true});

  final bool visible;

  @override
  ConsumerState<DailyCreditsCounter> createState() =>
      _DailyCreditsCounterState();
}

class _DailyCreditsCounterState extends ConsumerState<DailyCreditsCounter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  int _previousBalance = -1;
  bool _pulseScheduled = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _pulseAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.15)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.15, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
    ]).animate(_pulseController);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();

    final dailyCreditData = ref.watch(dailyCreditStateProvider);
    final balance = dailyCreditData.currentDailyCredits;

    if (_previousBalance >= 0 &&
        balance != _previousBalance &&
        !_pulseScheduled) {
      _pulseScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pulseScheduled = false;
        _pulseController.forward(from: 0);
      });
    }
    _previousBalance = balance;

    final cs = Theme.of(context).colorScheme;
    final hasError = dailyCreditData.errorMessage != null;
    final isPositive =
        !hasError && dailyCreditData.currentDailyCredits > 0;
    final labelColor = hasError ? cs.error : (isPositive ? cs.primary : cs.error);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) => Transform.scale(
          scale: _pulseAnimation.value,
          child: child,
        ),
        child: ActionChip(
          backgroundColor:
              labelColor.withValues(alpha: isPositive ? 0.10 : 0.12),
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
            hasError
                ? '—'
                : (dailyCreditData.loading
                    ? '…'
                    : '${dailyCreditData.currentDailyCredits}'),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: labelColor,
                  letterSpacing: 0.25,
                ),
          ),
          onPressed: () {
            if (dailyCreditData.currentDailyCredits <= 0) {
              context.push('/insufficient-offline-credit');
            } else {
              _showDailyCreditDetailsDialog(context, dailyCreditData);
            }
          },
        ),
      ),
    );
  }

  void _showDailyCreditDetailsDialog(BuildContext context, dynamic data) {
    final authData = ref.read(authProvider);
    final schoolTier = authData.currentSchool?.subscriptionTier ?? 'free';
    showDialog(
      context: context,
      builder: (_) => _DailyCreditsDetailsDialog(
        data: data,
        schoolTier: schoolTier,
      ),
    );
  }
}

class _DailyCreditsDetailsDialog extends StatelessWidget {
  const _DailyCreditsDetailsDialog({
    required this.data,
    required this.schoolTier,
  });

  final dynamic data;
  final String schoolTier;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
            child: Icon(
              Icons.account_balance_rounded,
              color: cs.onPrimaryContainer,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Daily Credits',
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Available daily credits',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        overflow: TextOverflow.clip,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${data.currentDailyCredits}',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                        letterSpacing: -0.25,
                        overflow: TextOverflow.clip,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Tier',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        overflow: TextOverflow.clip,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Chip(
                  label: Text(
                    data.tierName,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onPrimaryContainer,
                          overflow: TextOverflow.clip,
                        ),
                  ),
                  backgroundColor: cs.primaryContainer,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Plan',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        overflow: TextOverflow.clip,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Chip(
                  label: Text(
                    schoolTier.toLowerCase() == 'free'
                        ? 'Free Plan'
                        : '${schoolTier[0].toUpperCase()}${schoolTier.substring(1)} Plan',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSecondaryContainer,
                          overflow: TextOverflow.clip,
                        ),
                  ),
                  backgroundColor: cs.secondaryContainer,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
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
