// lib/features/payment/screens/payment_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:classai/core/services/payment_service.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Payment screen that shows plan selection options.
///
/// Selecting a plan calls [PaymentService.initializePayment]
/// and opens the returned Paystack checkout URL in a browser/WebView.
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
            onSelect: () => _initializePayment(context, ref, 'basic', 5000),
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
            onSelect: () => _initializePayment(context, ref, 'standard', 10000),
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
            onSelect: () => _initializePayment(context, ref, 'elite', 25000),
          ),
        ],
      ),
    );
  }

  Future<void> _initializePayment(
      BuildContext context, WidgetRef ref, String plan, int amountNaira) async {
    final authData = ref.read(authProvider);
    final teacher = authData.currentTeacher;
    final school = authData.currentSchool;

    if (teacher == null || school == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to purchase.')),
      );
      return;
    }

    try {
      final db = ref.read(databaseProvider);
      // Create a minimal Dio client for the payment API call
      final dio = Dio(BaseOptions(
        baseUrl: '', // base URL set in the Supabase Edge Function path
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      ));
      final paymentService = PaymentService(db, dio);

      final checkoutUrl = await paymentService.initializePayment(
        email: teacher.email,
        amountNaira: amountNaira,
        plan: plan,
        schoolId: school.serverId ?? school.localId.toString(),
      );

      if (!context.mounted) return;

      // Open the Paystack checkout URL in browser or WebView
      final uri = Uri.parse(checkoutUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback: try in-app WebView
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment initialization failed: $e')),
      );
    }
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
