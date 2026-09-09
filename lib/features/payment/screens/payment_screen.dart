// lib/features/payment/screens/payment_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:classai/core/constants/app_constants.dart';
import 'package:classai/core/providers/config_provider.dart';
import 'package:classai/core/services/payment_service.dart';
import 'package:classai/core/utils/currency_formatter.dart';
import 'package:classai/core/widgets/app_toast.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/main.dart' show databaseProvider;

Future<void> _showUpgradeSuccessOverlay(
  BuildContext context,
  String planName,
) async {
  if (!context.mounted) return;

  final overlayFuture = showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.24),
    useRootNavigator: true,
    builder: (dialogContext) {
      final dialogCs = Theme.of(dialogContext).colorScheme;
      final dialogTextTheme = Theme.of(dialogContext).textTheme;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: dialogCs.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: dialogCs.outlineVariant),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: dialogCs.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: dialogCs.onPrimaryContainer,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Subscription upgraded successfully!',
                    textAlign: TextAlign.center,
                    style: dialogTextTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You are now on the $planName plan.',
                    textAlign: TextAlign.center,
                    style: dialogTextTheme.bodyMedium?.copyWith(
                      color: dialogCs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Future.delayed(const Duration(seconds: 2), () {
    if (!context.mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  });

  await overlayFuture;
}

String _displayPlanName(String plan) {
  if (plan.isEmpty) return 'Selected';
  return plan[0].toUpperCase() + plan.substring(1).toLowerCase();
}

const Map<String, int> _tierRanks = <String, int>{
  'free': 0,
  'basic': 1,
  'standard': 2,
  'elite': 3,
};

int _tierRank(String tier) => _tierRanks[tier.toLowerCase()] ?? -1;

Widget _buildPlanActionButton({
  required ColorScheme cs,
  required TextTheme textTheme,
  required String tier,
  required String currentTier,
  required int currentTierRank,
  required VoidCallback? onPressed,
  required double width,
  required String enabledLabel,
}) {
  final planRank = _tierRank(tier);
  final bool isCurrentTier = tier.toLowerCase() == currentTier.toLowerCase();
  final bool isFreeTier = tier.toLowerCase() == 'free';
  final bool isEnabled = !isFreeTier && planRank > currentTierRank;
  final String label = isCurrentTier && !isFreeTier
      ? "You're on the ${_displayPlanName(tier)} Plan"
      : 'Unavailable';

  return SizedBox(
    width: width,
    height: 40,
    child: FilledButton(
      onPressed: isEnabled ? onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: isEnabled ? cs.primary : cs.surfaceContainerHighest,
        foregroundColor: isEnabled ? cs.onPrimary : cs.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      child: isEnabled
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_rounded,
                  size: 20,
                  color: cs.onPrimary,
                ),
                const SizedBox(width: 8),
                Text(
                  enabledLabel,
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: cs.onPrimary,
                  ),
                ),
              ],
            )
          : Text(
              label,
              textAlign: TextAlign.center,
              style: textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
    ),
  );
}

Widget _buildPlanCardsGrid({
  required ColorScheme cs,
  required TextTheme textTheme,
  required List<_TierComparisonRow> tiers,
  required String selectedTier,
  required String currentTier,
  required int currentTierRank,
  required double maxWidth,
  required ValueChanged<String> onSelectTier,
  required ValueChanged<String> onChoosePlan,
}) {
  // Responsive column count based on available width
  final int crossAxisCount;
  if (maxWidth < 600) {
    crossAxisCount = 1;
  } else if (maxWidth < 960) {
    crossAxisCount = 2;
  } else {
    crossAxisCount = 3;
  }

  const double spacing = 16;
  final double totalHorizontalSpacing = spacing * (crossAxisCount - 1);
  final double cardWidth = (maxWidth - totalHorizontalSpacing) / crossAxisCount;

  // Build rows manually to avoid GridView aspect-ratio issues with variable-height cards
  final List<Widget> rows = [];
  for (int i = 0; i < tiers.length; i += crossAxisCount) {
    final int end =
        (i + crossAxisCount > tiers.length) ? tiers.length : i + crossAxisCount;
    final List<Widget> cardsInRow = <Widget>[];
    for (int j = i; j < end; j++) {
      cardsInRow.add(
        SizedBox(
          width: cardWidth,
          child: _buildPlanCard(
            cs: cs,
            textTheme: textTheme,
            plan: tiers[j],
            isSelected: selectedTier == tiers[j].tier,
            currentTier: currentTier,
            currentTierRank: currentTierRank,
            onSelectTier: () => onSelectTier(tiers[j].tier),
            onChoosePlan: tiers[j].tier == 'free'
                ? null
                : () => onChoosePlan(tiers[j].tier),
          ),
        ),
      );
    }
    // Pad last row with empty spacers so all rows have the same height layout
    while (cardsInRow.length < crossAxisCount) {
      cardsInRow.add(SizedBox(width: cardWidth));
    }
    rows.add(
      Padding(
        padding: EdgeInsets.only(bottom: spacing),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: cardsInRow,
        ),
      ),
    );
  }

  return Column(children: rows);
}

Widget _buildPlanCard({
  required ColorScheme cs,
  required TextTheme textTheme,
  required _TierComparisonRow plan,
  required bool isSelected,
  required String currentTier,
  required int currentTierRank,
  required VoidCallback onSelectTier,
  required VoidCallback? onChoosePlan,
}) {
  final Color? cardBg = isSelected ? cs.primary.withValues(alpha: 0.08) : null;
  final Color borderColor =
      isSelected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.3);

  // Builds a single feature row: icon + label + value
  Widget _featureRow(String label, dynamic value) {
    final bool isBool = value is bool;
    final Widget leading = Icon(
      isBool
          ? (value ? Icons.check_rounded : Icons.remove_rounded)
          : Icons.check_rounded,
      size: 18,
      color: isBool
          ? (value ? cs.primary : cs.onSurfaceVariant)
          : cs.primary,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          if (!isBool)
            Text(
              '$value',
              style: textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
        ],
      ),
    );
  }

  return Container(
    decoration: BoxDecoration(
      color: cardBg ?? cs.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: borderColor),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSelectTier,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Plan name header
              Text(
                plan.name,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isSelected ? cs.primary : cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              // Price
              Text(
                plan.price,
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const Divider(height: 24),
              // Feature rows — one unified daily-credit quota per tier (2F.3)
              _featureRow('Daily credits', plan.dailyCredits),
              _featureRow('Subjects', plan.subjects),
              _featureRow('PDF exports', plan.pdfExports),
              _featureRow('Vault publishing', plan.vaultPublishing),
              _featureRow('Watermark', plan.watermark),
              _featureRow('Teacher seats', plan.teacherSeats),
              _featureRow('Lesson storage', plan.lessonStorage),
              _featureRow('AI diagrams', plan.aiDiagrams),
              _featureRow('Exam generation', plan.examGeneration),
              _featureRow('Bulk PDF export', plan.bulkPdfExport),
              const Divider(height: 24),
              // Action button
              _buildPlanActionButton(
                cs: cs,
                textTheme: textTheme,
                tier: plan.tier,
                currentTier: currentTier,
                currentTierRank: currentTierRank,
                onPressed: onChoosePlan,
                width: double.infinity,
                enabledLabel: 'Choose Plan',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

List<_TierComparisonRow> _buildTierComparisonRows(WidgetRef ref) {
  final config = ref.read(configServiceProvider);
  final prices = config.subscriptionPrices;
  final dailyCreditsLimits = config.dailyCreditsLimit;
  final pdfLimits = config.pdfExportLimits;
  final examGenTiers = config.examGenerationAllowedTiers;
  final bulkPdfTiers = config.bulkPdfExportAllowedTiers;
  final aiDiagramsTiers = config.aiDiagramsAllowedTiers;
  final topicRestrictions = config.topicRestrictionsByTier;

  String _subjectsLabel(String tier) {
    final allowed = topicRestrictions[tier];
    if (allowed == null || (allowed is List && allowed.isEmpty)) {
      return 'All subjects';
    }
    if (allowed is List) {
      final lower = allowed.map((e) => e.toString().toLowerCase()).toList();
      if (lower.contains('*')) return 'All subjects';
      if (lower.length <= 3) {
        return lower.map((s) => s[0].toUpperCase() + s.substring(1)).join(', ');
      }
      return '${lower.length} subjects';
    }
    return 'All subjects';
  }

  const fallbackTeacherSeats = <String, dynamic>{
    'free': 5, 'basic': 10, 'standard': 20, 'elite': 100,
  };
  const fallbackLessonStorage = <String, dynamic>{
    'free': 100, 'basic': 200, 'standard': 500, 'elite': -1,
  };

  final teacherSeatLimits = config.teacherSeatLimits.isNotEmpty
      ? config.teacherSeatLimits
      : fallbackTeacherSeats;
  final lessonStorageLimits = config.lessonStorageLimits.isNotEmpty
      ? config.lessonStorageLimits
      : fallbackLessonStorage;

  return [
    _TierComparisonRow(
      tier: 'free',
      name: 'Free',
      price: 'Free',
      dailyCredits: _tierLimitText(dailyCreditsLimits['free'], fallback: 3),
      subjects: _subjectsLabel('free'),
      pdfExports: _tierLimitText(pdfLimits['free'], fallback: 1),
      vaultPublishing: false,
      watermark: true,
      teacherSeats: _tierLimitText(teacherSeatLimits['free'], fallback: 5),
      lessonStorage: _tierLimitText(lessonStorageLimits['free'], fallback: 100),
      aiDiagrams: aiDiagramsTiers.contains('free'),
      examGeneration: examGenTiers.contains('free'),
      bulkPdfExport: bulkPdfTiers.contains('free'),
    ),
    _TierComparisonRow(
      tier: 'basic',
      name: 'Basic',
      price: _tierPrice(prices['basic'], AppConstants.basicPlanPriceNaira),
      dailyCredits: _tierLimitText(dailyCreditsLimits['basic'], fallback: 1),
      subjects: _subjectsLabel('basic'),
      pdfExports: _tierLimitText(pdfLimits['basic'], fallback: 3),
      vaultPublishing: false,
      watermark: false,
      teacherSeats: _tierLimitText(teacherSeatLimits['basic'], fallback: 10),
      lessonStorage: _tierLimitText(lessonStorageLimits['basic'], fallback: 200),
      aiDiagrams: aiDiagramsTiers.contains('basic'),
      examGeneration: examGenTiers.contains('basic'),
      bulkPdfExport: bulkPdfTiers.contains('basic'),
    ),
    _TierComparisonRow(
      tier: 'standard',
      name: 'Standard',
      price: _tierPrice(prices['standard'], AppConstants.standardPlanPriceNaira),
      dailyCredits: _tierLimitText(dailyCreditsLimits['standard'], fallback: 3),
      subjects: _subjectsLabel('standard'),
      pdfExports: _tierLimitText(pdfLimits['standard'], fallback: 5),
      vaultPublishing: true,
      watermark: false,
      teacherSeats: _tierLimitText(teacherSeatLimits['standard'], fallback: 20),
      lessonStorage: _tierLimitText(lessonStorageLimits['standard'], fallback: 500),
      aiDiagrams: aiDiagramsTiers.contains('standard'),
      examGeneration: examGenTiers.contains('standard'),
      bulkPdfExport: bulkPdfTiers.contains('standard'),
    ),
    _TierComparisonRow(
      tier: 'elite',
      name: 'Elite',
      price: _tierPrice(prices['elite'], AppConstants.elitePlanPriceNaira),
      dailyCredits: _tierLimitText(dailyCreditsLimits['elite'], fallback: -1),
      subjects: _subjectsLabel('elite'),
      pdfExports: _tierLimitText(pdfLimits['elite'], fallback: -1),
      vaultPublishing: true,
      watermark: false,
      teacherSeats: _tierLimitText(teacherSeatLimits['elite'], fallback: 100),
      lessonStorage: _tierLimitText(lessonStorageLimits['elite'], fallback: -1),
      aiDiagrams: aiDiagramsTiers.contains('elite'),
      examGeneration: examGenTiers.contains('elite'),
      bulkPdfExport: bulkPdfTiers.contains('elite'),
    ),
  ];
}

String _tierPrice(dynamic value, int fallback) {
  final amount = value is int
      ? value
      : value is num
          ? value.toInt()
          : fallback;
  return '${CurrencyFormatter.formatNairaCompact(amount)}/yr';
}

String _tierLimitText(dynamic value, {required int fallback}) {
  final limit = value is int
      ? value
      : value is num
          ? value.toInt()
          : fallback;
  if (limit < 0) return 'Unlimited';
  return limit.toString();
}

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  bool _isProcessing = false;
  String _selectedPlanTier = 'elite';
  bool _didInitPlan = false;
  late ValueNotifier<String> _selectedTierNotifier;
  List<_TierComparisonRow> _tiers = [];

  // ── Polling state tracking (M1) ────────────────────────────────────
  bool _isPolling = false;
  bool _hasPollTimedOut = false;
  String? _lastReference;
  String? _lastPlan;
  String? _lastSchoolId;
  PaymentService? _lastPaymentService;

  @override
  void initState() {
    super.initState();
    _selectedTierNotifier = ValueNotifier<String>('elite');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumePendingPayments();
      setState(() {
        _tiers = _buildTierComparisonRows(ref);
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitPlan) return;

    final plan = GoRouterState.of(context).uri.queryParameters['plan']
        ?.toLowerCase();
    switch (plan) {
      case 'basic':
      case 'standard':
      case 'elite':
        _selectedPlanTier = plan!;
        _selectedTierNotifier.value = _selectedPlanTier;
        break;
      default:
        _selectedPlanTier = 'elite';
        _selectedTierNotifier.value = 'elite';
        break;
    }
    _didInitPlan = true;
  }

  @override
  void dispose() {
    _selectedTierNotifier.dispose();
    super.dispose();
  }

  List<_PlanDef> _buildPlans() {
    final config = ref.read(configServiceProvider);
    final prices = config.subscriptionPrices;
    return [
      _PlanDef(
        name: 'Basic',
        amountNaira: prices['basic'] as int? ?? AppConstants.basicPlanPriceNaira,
        tier: 'basic',
      ),
      _PlanDef(
        name: 'Standard',
        amountNaira:
            prices['standard'] as int? ?? AppConstants.standardPlanPriceNaira,
        tier: 'standard',
      ),
      _PlanDef(
        name: 'Elite',
        amountNaira: prices['elite'] as int? ?? AppConstants.elitePlanPriceNaira,
        tier: 'elite',
      ),
    ];
  }

  _PlanDef _planDefFromTierRow(_TierComparisonRow row) {
    final plans = _buildPlans();
    return plans.firstWhere(
      (plan) => plan.tier == row.tier,
      orElse: () => plans.last,
    );
  }

  Future<void> _resumePendingPayments() async {
    final authData = ref.read(authProvider);
    final school = authData.currentSchool;
    final teacher = authData.currentTeacher;
    if (school == null || teacher == null) return;

    try {
      final db = ref.read(databaseProvider);
      final pendingPayments = await db.paymentEventsDao.getUnconfirmed();
      if (pendingPayments.isEmpty || !mounted) return;

      final paymentService = PaymentService(db);
      final schoolId = school.serverId ?? school.localId.toString();
      final currentTier = school.subscriptionTier.toLowerCase();
      final currentTierRank = _tierRank(currentTier);

      for (final payment in pendingPayments) {
        if (!mounted) break; // exit early if screen was disposed

        // ── Downgrade guard: only auto-resume genuine upgrades ──────────
        // A stale unconfirmed payment (e.g. an old Basic checkout) must never
        // downgrade a currently higher tier. Skip and leave the row for
        // manual review — same-tier renewals are user-triggered from the
        // Payment screen instead.
        final pendingPlanRank = _tierRank(payment.plan);
        if (pendingPlanRank <= currentTierRank) {
          debugPrint(
            '[PAYMENT-RESUME] Skipping pending ${payment.plan} payment — current '
            'tier is $currentTier and this is not an upgrade.',
          );
          continue;
        }

        try {
          final confirmed = await paymentService.verifyPayment(
            payment.transactionReference,
          );
          if (!confirmed) {
            continue; // not yet confirmed by Paystack, try the next one
          }
          if (!mounted) break;
          await _confirmAndShowCode(
            context,
            ref,
            paymentService,
            payment.transactionReference,
            payment.plan,
            schoolId,
          );
          // Continue processing remaining rows — do NOT break
        } catch (_) {
          // Individual row failed; move to the next without aborting
          continue;
        }
      }
    } catch (_) {
      // Top-level error from db read or setup; nothing to recover
    }
  }

  Future<void> _initializePayment(
    BuildContext context,
    WidgetRef ref,
    String plan,
    int amountNaira,
  ) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final authData = ref.read(authProvider);
    final teacher = authData.currentTeacher;
    final school = authData.currentSchool;

    if (teacher == null || school == null) {
      if (!context.mounted) return;
      setState(() => _isProcessing = false);
      showErrorToast(
        context: context,
        message: 'You must be logged in to purchase.',
      );
      return;
    }

    final schoolId = school.serverId ?? school.localId.toString();

    try {
      final db = ref.read(databaseProvider);
      final paymentService = PaymentService(db);

      final initResult = await paymentService.initializePayment(
        email: teacher.email,
        amountNaira: amountNaira,
        plan: plan,
        schoolId: schoolId,
      );

      if (!context.mounted) return;

      final uri = Uri.parse(initResult.checkoutUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }

      final reference = initResult.reference;
      if (!context.mounted) return;

      // Store polling context for potential retry
      _lastPaymentService = paymentService;
      _lastReference = reference;
      _lastPlan = plan;
      _lastSchoolId = schoolId;
      _hasPollTimedOut = false;

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
        context: context,
        message: 'Payment initialization failed: $e',
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
    // Guard against concurrent polling loops
    if (_isPolling) return;
    _isPolling = true;
    _hasPollTimedOut = false;
    if (mounted) setState(() {});

    if (!context.mounted) {
      _isPolling = false;
      if (mounted) setState(() {});
      return;
    }

    showInfoToast(
      context: context,
      message: 'Waiting for payment confirmation...',
    );

    for (int i = 0; i < 10; i++) {
      final confirmed = await paymentService.verifyPayment(reference);
      if (confirmed) {
        if (!context.mounted) {
          _isPolling = false;
          if (mounted) setState(() {});
          return;
        }
        _isPolling = false;
        if (mounted) setState(() {});
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

    if (!context.mounted) {
      _isPolling = false;
      if (mounted) setState(() {});
      return;
    }

    _isPolling = false;
    _hasPollTimedOut = true;
    if (mounted) setState(() {});
    showErrorToast(
      context: context,
      message:
          'Payment confirmation timed out. Your payment may still have processed. Please check your email for a receipt.',
    );
  }

  /// Retry polling after a timeout — called by the "Check Payment Status" button.
  /// Guards against an already-in-flight poll and reuses the stored polling context.
  Future<void> _retryPoll() async {
    if (_isPolling) return;
    if (_lastPaymentService == null ||
        _lastReference == null ||
        _lastPlan == null ||
        _lastSchoolId == null) return;

    await _pollForPayment(
      context,
      ref,
      _lastPaymentService!,
      _lastReference!,
      _lastPlan!,
      _lastSchoolId!,
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
      await paymentService.confirmPayment(
        reference: reference,
        plan: plan,
        schoolId: schoolId,
      );

      if (!context.mounted) return;

      await ref.read(authProvider.notifier).refreshSchoolFromDb();

      await _showUpgradeSuccessOverlay(
        context,
        _displayPlanName(plan),
      );

      if (context.mounted) {
        GoRouter.of(context).pop();
      }
    } catch (e) {
      if (!context.mounted) return;
      showErrorToast(
        context: context,
        message: 'Failed to confirm payment: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final authData = ref.watch(authProvider);
    final currentTier = (authData.currentSchool?.subscriptionTier ?? 'free')
        .toLowerCase();
    final currentTierRank = _tierRank(currentTier);

    if (_tiers.isEmpty) {
      // Rebuild tiers if not yet initialized
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _tiers = _buildTierComparisonRows(ref);
          });
        }
      });
    }

    final screenSize = MediaQuery.sizeOf(context);
    final screenWidth = screenSize.width;
    final double horizontalPadding = 24.0 + 24.0;
    final double gridAvailableWidth = screenWidth - horizontalPadding;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: cs.onSurface),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(''),
        centerTitle: false,
      ),
      body: _tiers.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ValueListenableBuilder<String>(
              valueListenable: _selectedTierNotifier,
              builder: (context, selectedTier, _) {
                final selectedTierRow = _tiers.firstWhere(
                  (t) => t.tier == selectedTier,
                  orElse: () => _tiers.last,
                );

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.workspace_premium_rounded,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Compare Plans',
                                  style: textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Review the tiers before you continue to checkout.',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Plan cards grid — responsive column count via maxWidth
                      _buildPlanCardsGrid(
                        cs: cs,
                        textTheme: textTheme,
                        tiers: _tiers,
                        selectedTier: selectedTier,
                        currentTier: currentTier,
                        currentTierRank: currentTierRank,
                        maxWidth: gridAvailableWidth,
                        onSelectTier: (tier) =>
                            _selectedTierNotifier.value = tier,
                        onChoosePlan: (tier) {
                          _selectedPlanTier = tier;
                          _selectedTierNotifier.value = tier;
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 20),
                      // Order summary
                      SizedBox(
                        width: gridAvailableWidth.clamp(0, 500),
                        child: _buildOrderSummary(
                          context,
                          cs,
                          textTheme,
                          currentTier,
                          currentTierRank,
                          _planDefFromTierRow(selectedTierRow),
                        ),
                      ),
                      if (_isProcessing)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (_hasPollTimedOut)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Column(
                            children: [
                              Text(
                                'Your payment may still have processed. Please check your email for a receipt.',
                                textAlign: TextAlign.center,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _retryPoll,
                                icon: const Icon(Icons.refresh_rounded, size: 20),
                                label: const Text('Check Payment Status'),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildOrderSummary(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    String currentTier,
    int currentTierRank,
    _PlanDef plan,
  ) {
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
                  '${plan.price}/yr',
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
                  textAlign: TextAlign.center,
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
          _buildPlanActionButton(
            cs: cs,
            textTheme: textTheme,
            tier: plan.tier,
            currentTier: currentTier,
            currentTierRank: currentTierRank,
            onPressed: _isProcessing
                ? null
                : () => _initializePayment(
                      context,
                      ref,
                      plan.tier,
                      plan.amountNaira,
                    ),
            width: double.infinity,
            enabledLabel: 'Proceed to Checkout',
          ),
          const SizedBox(height: 16),
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

class _PlanDef {
  final String name;
  final int amountNaira;
  final String tier;

  const _PlanDef({
    required this.name,
    required this.amountNaira,
    required this.tier,
  });

  String get price => CurrencyFormatter.formatNairaCompact(amountNaira);
}

class _TierComparisonRow {
  final String tier;
  final String name;
  final String price;
  final String dailyCredits;
  final String subjects;
  final String pdfExports;
  final bool vaultPublishing;
  final bool watermark;
  final String teacherSeats;
  final String lessonStorage;
  final bool aiDiagrams;
  final bool examGeneration;
  final bool bulkPdfExport;


  const _TierComparisonRow({
    required this.tier,
    required this.name,
    required this.price,
    required this.dailyCredits,
    required this.subjects,
    required this.pdfExports,
    required this.vaultPublishing,
    required this.watermark,
    required this.teacherSeats,
    required this.lessonStorage,
    required this.aiDiagrams,
    required this.examGeneration,
    required this.bulkPdfExport,
  });
}
