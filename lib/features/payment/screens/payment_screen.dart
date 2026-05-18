// lib/features/payment/screens/payment_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// After the user completes payment in the browser, the screen polls
/// for confirmation and displays the activation code.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  bool _isProcessing = false;

  Future<void> _initializePayment(
      BuildContext context, WidgetRef ref, String plan, int amountNaira) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final authData = ref.read(authProvider);
    final teacher = authData.currentTeacher;
    final school = authData.currentSchool;

    if (teacher == null || school == null) {
      if (!context.mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to purchase.')),
      );
      return;
    }

    final schoolId = school.serverId ?? school.localId.toString();

    try {
      final db = ref.read(databaseProvider);
      // Create a minimal Dio client for the payment API call
      final dio = Dio(BaseOptions(
        baseUrl: '',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      ));
      final paymentService = PaymentService(db, dio);

      final initResult = await paymentService.initializePayment(
        email: teacher.email,
        amountNaira: amountNaira,
        plan: plan,
        schoolId: schoolId,
      );

      if (!context.mounted) return;

      // Open the Paystack checkout URL in browser
      final uri = Uri.parse(initResult.checkoutUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }

      // Store the reference for polling
      final reference = initResult.reference;

      // Start polling for payment confirmation
      if (!context.mounted) return;
      await _pollForPayment(
        context,
        ref,
        paymentService,
        reference,
        plan,
        schoolId,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment initialization failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _pollForPayment(
    BuildContext context,
    WidgetRef ref,
    PaymentService paymentService,
    String reference,
    String plan,
    String schoolId,
  ) async {
    // Show a snackbar indicating we're waiting for payment
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Waiting for payment confirmation…'),
        duration: Duration(seconds: 5),
      ),
    );

    // Poll up to 10 times (30 seconds apart = 5 minutes total)
    for (int i = 0; i < 10; i++) {
      final confirmed = await paymentService.verifyPayment(reference);

      if (confirmed) {
        if (!context.mounted) return;
        // Payment confirmed — call the Edge Function to generate activation code
        await _confirmAndShowCode(
          context,
          ref,
          paymentService,
          reference,
          plan,
          schoolId,
        );
        return;
      }

      if (i < 9) {
        await Future.delayed(const Duration(seconds: 30));
      }
    }

    // Polling timed out
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Payment confirmation timed out. Your payment may still have '
          'processed. Please check your email for a receipt.',
        ),
        duration: Duration(seconds: 10),
      ),
    );
  }

  Future<void> _confirmAndShowCode(
    BuildContext context,
    WidgetRef ref,
    PaymentService paymentService,
    String reference,
    String plan,
    String schoolId,
  ) async {
    try {
      // Call the Edge Function to generate activation code and update the school
      final confirmation = await paymentService.confirmPayment(
        reference: reference,
        plan: plan,
        schoolId: schoolId,
      );

      if (!context.mounted) return;

      // Show activation code dialog
      await _showActivationCodeDialog(context, confirmation.activationCode);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to confirm payment: $e'),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  Future<void> _showActivationCodeDialog(
      BuildContext context, String activationCode) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade700),
              const SizedBox(width: 8),
              const Text('Payment Successful!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your plan has been upgraded. Keep this activation code '
                'for your records.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SelectableText(
                  activationCode,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your activation code: $activationCode',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: activationCode));
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Activation code copied to clipboard!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upgrade Plan'),
      ),
      body: Stack(
        children: [
          ListView(
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
                features: [
                  '50 credits per month',
                  'Access to basic vault items',
                ],
                onSelect: _isProcessing
                    ? null
                    : () => _initializePayment(context, ref, 'basic', 5000),
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
                onSelect: _isProcessing
                    ? null
                    : () =>
                        _initializePayment(context, ref, 'standard', 10000),
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
                onSelect: _isProcessing
                    ? null
                    : () => _initializePayment(context, ref, 'elite', 25000),
              ),
            ],
          ),
          if (_isProcessing)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Processing payment…',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
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
  final VoidCallback? onSelect;

  const _PlanCard({
    required this.name,
    required this.price,
    required this.credits,
    required this.tier,
    required this.color,
    required this.features,
    this.isPopular = false,
    this.onSelect,
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
