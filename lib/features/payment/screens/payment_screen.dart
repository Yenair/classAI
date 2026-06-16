// lib/features/payment/screens/payment_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:classai/core/services/payment_service.dart';
import 'package:classai/core/widgets/app_toast.dart';
import 'package:classai/core/constants/app_constants.dart';
import 'package:classai/core/utils/currency_formatter.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Payment screen that shows plan selection options — Google Stitch design.
///
/// Selecting a plan calls [PaymentService.initializePayment]
/// and opens the returned Paystack authorization URL in a browser/WebView.
/// After the user completes payment in the browser, the screen polls
/// for confirmation and displays the activation code.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  bool _isProcessing = false;
  String _selectedPlan = 'standard';

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
      showErrorToast(
          context: context, message: 'You must be logged in to purchase.');
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

      // Open the Paystack authorization URL in browser
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
      showErrorToast(
          context: context, message: 'Payment initialization failed: $e');
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
    showInfoToast(
        context: context, message: 'Waiting for payment confirmation\u2026');

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
    showErrorToast(
      context: context,
      message:
          'Payment confirmation timed out. Your payment may still have processed. Please check your email for a receipt.',
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

      // Refresh the auth provider so the free-plan banner, credit dialog tier,
      // and other tier-dependent widgets react immediately.
      ref.read(authProvider.notifier).refreshSchoolFromDb();

      // Show activation code dialog
      await _showActivationCodeDialog(context, confirmation.activationCode);
    } catch (e) {
      if (!context.mounted) return;
      showErrorToast(
          context: context, message: 'Failed to confirm payment: $e');
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          title: Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: cs.primary.withValues(alpha: 0.9)),
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
                  borderRadius: BorderRadius.circular(8),
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

  // Plan definitions
  static const _plans = [
    _PlanDef(
      name: 'Basic',
      amountNaira: AppConstants.basicPlanPriceNaira,
      tier: 'basic',
      description: 'Essential tools for small classrooms. Up to 30 students.',
      features: ['50 credits per month', 'Access to basic vault items'],
    ),
    _PlanDef(
      name: 'Standard',
      amountNaira: AppConstants.standardPlanPriceNaira,
      tier: 'standard',
      description:
          'Advanced analytics and resources. Up to 100 students.',
      features: [
        '120 credits per month',
        'Access to standard vault items',
        'Vault publishing',
      ],
      isBestValue: true,
    ),
    _PlanDef(
      name: 'Elite',
      amountNaira: AppConstants.elitePlanPriceNaira,
      tier: 'elite',
      description:
          'Unlimited students, priority support, and custom modules.',
      features: [
        '350 credits per month',
        'Full vault access',
        'Priority support',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isWide = MediaQuery.of(context).size.width >= 1024;

    final selectedPlan =
        _plans.firstWhere((p) => p.tier == _selectedPlan);

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mobile TopAppBar (Stitch style)
                if (!isWide)
                  _buildMobileHeader(context, cs, textTheme, selectedPlan),

                // Main Canvas
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 1280,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header Section
                              _buildHeader(context, cs, textTheme),

                              const SizedBox(height: 32),

                              // Plans + Summary grid
                              isWide
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Left: Pricing cards
                                        Expanded(
                                          flex: 7,
                                          child: _buildPlansList(
                                              cs, textTheme),
                                        ),
                                        const SizedBox(width: 32),
                                        // Right: Order Summary
                                        Expanded(
                                          flex: 5,
                                          child: _buildOrderSummary(
                                              context, cs, textTheme,
                                              selectedPlan),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Pricing cards
                                        _buildPlansList(cs, textTheme),
                                        const SizedBox(height: 32),
                                        // Order Summary
                                        _buildOrderSummary(
                                            context, cs, textTheme,
                                            selectedPlan),
                                      ],
                                    ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Processing overlay
          if (_isProcessing)
            Positioned.fill(
              child: ColoredBox(
                color: cs.scrim,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Processing payment\u2026',
                        style: TextStyle(
                          color: cs.onPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Mobile Header (Stitch)
  // ---------------------------------------------------------------
  Widget _buildMobileHeader(
      BuildContext context, ColorScheme cs, TextTheme textTheme, _PlanDef selectedPlan) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(
            color: cs.surfaceContainerHighest,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            'ClassAI',
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.primary,
            ),
          ),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              selectedPlan.price,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Header Section
  // ---------------------------------------------------------------
  Widget _buildHeader(
      BuildContext context, ColorScheme cs, TextTheme textTheme) {
    return Row(
      children: [
        // Back button
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: cs.surface,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: cs.onSurface,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Upgrade Your Plan',
                style: (textTheme.headlineSmall ?? textTheme.titleLarge)
                    ?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Select the package that best fits your classroom needs.',
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------
  // Plans List (Radio Card selection)
  // ---------------------------------------------------------------
  Widget _buildPlansList(ColorScheme cs, TextTheme textTheme) {
    return Column(
      children: _plans.map((plan) {
        final isSelected = _selectedPlan == plan.tier;
        return GestureDetector(
          onTap: () => setState(() => _selectedPlan = plan.tier),
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: Stack(
              children: [
                // Best Value badge
                if (plan.isBestValue)
                  Positioned(
                    top: -12,
                    right: 24,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: cs.shadow.withValues(alpha: 0.1),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: cs.onPrimaryContainer,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Best Value',
                            style: textTheme.labelMedium?.copyWith(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? cs.primary
                          : cs.outlineVariant.withValues(alpha: 0.3),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Radio circle
                      Container(
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? cs.primary
                                : cs.outlineVariant,
                            width: 2,
                          ),
                          color: isSelected ? cs.primary : Colors.transparent,
                        ),
                        child: isSelected
                            ? Center(
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: cs.onPrimary,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),

                      // Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan.name,
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              plan.description,
                              style: textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Price
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            plan.price,
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            '/yr',
                            style: textTheme.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------
  // Order Summary
  // ---------------------------------------------------------------
  Widget _buildOrderSummary(BuildContext context, ColorScheme cs,
      TextTheme textTheme, _PlanDef plan) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.onSurface.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            'Order Summary',
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),

          // Selected Plan
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Selected Plan',
                  style: textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  plan.name,
                  textAlign: TextAlign.end,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Duration
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Duration',
                  style: textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '1 Year',
                  textAlign: TextAlign.end,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),

          // Total Due
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Total Due',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  plan.price,
                  textAlign: TextAlign.end,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Payment provider placeholder
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 48,
                  color: cs.outline,
                ),
                const SizedBox(height: 8),
                Text(
                  'Secure checkout powered by Paystack.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '(WebView Container)',
                  style: textTheme.labelSmall?.copyWith(
                    color: cs.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Proceed to Checkout button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _isProcessing
                  ? null
                  : () => _initializePayment(
                        context,
                        ref,
                        plan.tier,
                        plan.amountNaira,
                      ),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_rounded,
                    size: 20,
                    color: cs.onPrimary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Proceed to Checkout',
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: cs.onPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Security note
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.verified_user_rounded,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Bank-grade security',
                style: textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Internal plan definition.
class _PlanDef {
  final String name;
  final int amountNaira;
  final String tier;
  final String description;
  final List<String> features;
  final bool isBestValue;

  const _PlanDef({
    required this.name,
    required this.amountNaira,
    required this.tier,
    required this.description,
    this.features = const [],
    this.isBestValue = false,
  });

  /// Computed price string using the shared currency formatter.
  String get price =>
      '${CurrencyFormatter.formatNairaCompact(amountNaira)}/yr';
}
