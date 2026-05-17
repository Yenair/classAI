// lib/features/payment/screens/payment_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Payment screen that shows plan selection options.
///
/// In production, selecting a plan calls [PaymentService.initializePayment]
/// and opens the returned Paystack checkout URL in a WebView or external
/// browser. For now, this demonstrates the plan selection UI and flows.
class PaymentScreen extends ConsumerWidget {
  const PaymentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upgrade Plan'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.lock_outline,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Choose a plan to get more credits',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 32),
          _PlanCard(
            name: 'Basic',
            price: '₦5,000/mo',
            credits: 50,
            tier: 'basic',
            color: Colors.blue,
            features: ['50 credits per month', 'Access to basic vault items'],
            onSelect: () => _showPaymentConfirmation(context, 'basic', 5000),
          ),
          const SizedBox(height: 16),
          _PlanCard(
            name: 'Standard',
            price: '₦10,000/mo',
            credits: 120,
            tier: 'standard',
            color: Colors.purple,
            features: [
              '120 credits per month',
              'Access to standard vault items',
              'Vault publishing',
            ],
            isPopular: true,
            onSelect: () => _showPaymentConfirmation(context, 'standard', 10000),
          ),
          const SizedBox(height: 16),
          _PlanCard(
            name: 'Elite',
            price: '₦25,000/mo',
            credits: 350,
            tier: 'elite',
            color: Colors.amber,
            features: [
              '350 credits per month',
              'Full vault access',
              'Priority support',
            ],
            onSelect: () => _showPaymentConfirmation(context, 'elite', 25000),
          ),
        ],
      ),
    );
  }

  void _showPaymentConfirmation(
      BuildContext context, String plan, int amountNaira) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Upgrade'),
        content: Text(
          'You are about to purchase the $plan plan for '
          '₦${amountNaira.toStringAsFixed(0)}/month. '
          'Proceed to payment?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Payment flow started for $plan plan. '
                    'In production, the Paystack checkout page opens here.',
                  ),
                ),
              );
            },
            child: const Text('Proceed'),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String name;
  final String price;
  final int credits;
  final String tier;
  final Color color;
  final List<String> features;
  final bool isPopular;
  final VoidCallback onSelect;

  const _PlanCard({
    required this.name,
    required this.price,
    required this.credits,
    required this.tier,
    required this.color,
    required this.features,
    this.isPopular = false,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: isPopular ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPopular
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isPopular)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'MOST POPULAR',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            if (isPopular) const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              price,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            Text(
              '$credits credits per month',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.check, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(f, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onSelect,
                style: isPopular
                    ? FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                      )
                    : null,
                child: Text('Choose $name'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
