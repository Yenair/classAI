import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Screen shown when the user has insufficient offline credits.
///
/// Displays options to purchase more offline credits or learn about
/// offline credit tiers.
class InsufficientOfflineCreditScreen extends StatelessWidget {
  const InsufficientOfflineCreditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insufficient Offline Credits'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.monetization_on_outlined,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              'You need offline credits to use this feature',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Purchase a plan to get more offline credits for generating content.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.push('/payment'),
              icon: const Icon(Icons.shopping_cart),
              label: const Text('View Plans'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}
