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
        content: Text('Waiting for payment confirmation\u2026'),
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
    final cs = Theme.of(context).colorScheme;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: Colors.green.withValues(alpha: 0.9)),
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
                  horizontal: 18,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: SelectableText(
                  activationCode,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Copy and save your activation code:',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 18),
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upgrade Plan'),
        elevation: 0,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 72,
                color: cs.primary.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Choose a plan to get more credits',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ),
              const SizedBox(height: 32),
              _PlanCard(
                name: 'Basic',
                price: '\u20A649,999/yr',
                credits: 50,
                tier: 'basic',
                cs: cs,
                features: [
                  '50 credits per month',
                  'Access to basic vault items',
                ],
                onSelect: _isProcessing
                    ? null
                    : () => _initializePayment(context, ref, 'basic', 49999),
              ),
              const SizedBox(height: 16),
              _PlanCard(
                name: 'Standard',
                price: '\u20A699,999/yr',
                credits: 120,
                tier: 'standard',
                cs: cs,
                features: [
                  '120 credits per month',
                  'Access to standard vault items',
                  'Vault publishing',
                ],
                isPopular: true,
                onSelect: _isProcessing
                    ? null
                    : () => _initializePayment(context, ref, 'standard', 99999),
              ),
              const SizedBox(height: 16),
              _PlanCard(
                name: 'Elite',
                price: '\u20A6249,999/yr',
                credits: 350,
                tier: 'elite',
                cs: cs,
                features: [
                  '350 credits per month',
                  'Full vault access',
                  'Priority support',
                ],
                onSelect: _isProcessing
                    ? null
                    : () => _initializePayment(context, ref, 'elite', 249999),
              ),
            ],
          ),
          if (_isProcessing)
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.32),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Processing payment\u2026',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
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
  final ColorScheme cs;
  final List<String> features;
  final bool isPopular;
  final VoidCallback? onSelect;

  const _PlanCard({
    required this.name,
    required this.price,
    required this.credits,
    required this.tier,
    required this.cs,
    required this.features,
    this.isPopular = false,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPopular
              ? cs.primary.withValues(alpha: 0.45)
              : cs.outlineVariant.withValues(alpha: 0.45),
          width: isPopular ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.onSurface.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isPopular)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                margin: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'MOST POPULAR',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimaryContainer,
                        letterSpacing: 0.6,
                      ),
                ),
              ),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              price,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
            ),
            Text(
              '$credits credits per month',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        f,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onSelect,
                style: isPopular
                    ? FilledButton.styleFrom(
                        backgroundColor: cs.primary,
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
