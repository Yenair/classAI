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


Widget _buildComparisonTable(
  ColorScheme cs,
  TextTheme textTheme,
  List<_TierComparisonRow> tiers,
  {
  required String selectedTier,
  required ValueChanged<String> onSelectTier,
  required ValueChanged<String> onChoosePlan,
  double availableWidth = 0,
}
) {
  // Determine column widths responsively
  const double labelColumnWidth = 140;
  const int totalPlanColumns = 4;
  final double planColumnWidth;

  if (availableWidth > 0) {
    final double remaining = availableWidth - labelColumnWidth;
    planColumnWidth = (remaining / totalPlanColumns).clamp(160, 260);
  } else {
    planColumnWidth = 200;
  }

  final List<_BuildColumnContext> colContexts = [
    _BuildColumnContext(
      plan: tiers[0],
      headerColor: cs.primaryContainer.withValues(alpha: 0.35),
      isSelected: selectedTier == tiers[0].tier,
      isClickable: tiers[0].tier != 'free',
    ),
    _BuildColumnContext(
      plan: tiers[1],
      headerColor: cs.tertiaryContainer.withValues(alpha: 0.35),
      isSelected: selectedTier == tiers[1].tier,
      isClickable: tiers[1].tier != 'free',
    ),
    _BuildColumnContext(
      plan: tiers[2],
      headerColor: cs.secondaryContainer.withValues(alpha: 0.35),
      isSelected: selectedTier == tiers[2].tier,
      isClickable: tiers[2].tier != 'free',
    ),
    _BuildColumnContext(
      plan: tiers[3],
      headerColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      isSelected: selectedTier == tiers[3].tier,
      isClickable: tiers[3].tier != 'free',
    ),
  ];

  // --- Cell building helpers ---

  Widget labelCell(
    String text, {
    TextStyle? style,
    Color? backgroundColor,
  }) {
    return Container(
      width: labelColumnWidth,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: backgroundColor ?? cs.surfaceContainerLow,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: style,
      ),
    );
  }

  Widget iconCell(bool included, {Color? backgroundColor}) {
    return Container(
      width: planColumnWidth,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor ?? cs.surface,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Icon(
        included ? Icons.check_rounded : Icons.remove_rounded,
        size: 18,
        color: included ? cs.primary : cs.onSurfaceVariant,
      ),
    );
  }

  Widget textCell(String text, {Color? backgroundColor, TextStyle? style}) {
    return Container(
      width: planColumnWidth,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor ?? cs.surface,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: style ?? textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
    );
  }

  // Build one whole column for a plan
  Widget _buildPlanColumn(_BuildColumnContext ctx) {
    final plan = ctx.plan;
    final bgColor = ctx.isSelected
        ? cs.primary.withValues(alpha: 0.12)
        : (ctx.isClickable ? ctx.headerColor : null);
    final borderColor = ctx.isSelected
        ? cs.primary
        : cs.outlineVariant.withValues(alpha: 0.2);

    final List<Widget> cells = [
      // Header: plan name
      Container(
        width: planColumnWidth,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor),
        ),
        child: Text(
          plan.name,
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: ctx.isSelected ? cs.primary : cs.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
      ),
      // Price row
      textCell(
        plan.price,
        backgroundColor: bgColor,
        style: textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: ctx.isSelected ? cs.primary : cs.onSurface,
        ),
      ),
      // Daily previews
      textCell(plan.dailyPreviews, backgroundColor: bgColor),
      // PDF exports
      textCell(plan.pdfExports, backgroundColor: bgColor),
      // Vault publishing
      iconCell(plan.vaultPublishing, backgroundColor: bgColor),
      // Watermark
      iconCell(plan.watermark, backgroundColor: bgColor),
      // Teacher seats
      textCell(plan.teacherSeats, backgroundColor: bgColor),
      // Lesson storage
      textCell(plan.lessonStorage, backgroundColor: bgColor),
      // AI diagrams
      iconCell(plan.aiDiagrams, backgroundColor: bgColor),
      // Exam generation
      iconCell(plan.examGeneration, backgroundColor: bgColor),
      // Bulk PDF export
      iconCell(plan.bulkPdfExport, backgroundColor: bgColor),
    ];

    // Action row: Choose Plan button for paid plans, "Unavailable" for free
    if (!ctx.isClickable) {
      cells.add(
        Container(
          width: planColumnWidth,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
          ),
          child: Text(
            'Unavailable',
            style: textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    } else {
      cells.add(
        Container(
          width: planColumnWidth,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor),
          ),
          child: SizedBox(
            width: planColumnWidth - 16,
            height: 40,
            child: FilledButton(
              onPressed: () => onChoosePlan(plan.tier),
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Text(
                'Choose Plan',
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onPrimary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: cells,
    );

    final Widget sizedColumn = SizedBox(
      width: planColumnWidth,
      child: column,
    );

    // Paid columns are entirely tappable; Free is static
    // Use GestureDetector instead of InkWell to avoid hit-test/layout race
    // that causes "RenderBox was not laid out" / "hasSize" errors.
    if (ctx.isClickable) {
      return GestureDetector(
        onTap: () => onSelectTier(plan.tier),
        child: sizedColumn,
      );
    }

    return sizedColumn;
  }

  // Build the full table as a Row (label column + 4 plan columns)
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      // Feature labels column — wrapped in SizedBox so CrossAxisAlignment.stretch
      // never receives infinite width from the horizontal scroll view
      SizedBox(
        width: labelColumnWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            labelCell('Plan', style: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            )),
            labelCell('Price per year', style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            )),
            labelCell('Daily previews', style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            )),
            labelCell('PDF exports', style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            )),
            labelCell('Vault publishing', style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            )),
            labelCell('Watermark', style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            )),
            labelCell('Teacher seats', style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            )),
            labelCell('Lesson storage', style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            )),
            labelCell('AI diagrams', style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            )),
            labelCell('Exam generation', style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            )),
            labelCell('Bulk PDF export', style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            )),
            labelCell('', style: null), // empty cell for action row alignment
          ],
        ),
      ),
      // Plan columns
      _buildPlanColumn(colContexts[0]),
      _buildPlanColumn(colContexts[1]),
      _buildPlanColumn(colContexts[2]),
      _buildPlanColumn(colContexts[3]),
    ],
  );
}

class _BuildColumnContext {
  final _TierComparisonRow plan;
  final Color headerColor;
  final bool isSelected;
  final bool isClickable;

  const _BuildColumnContext({
    required this.plan,
    required this.headerColor,
    required this.isSelected,
    required this.isClickable,
  });
}

List<_TierComparisonRow> _buildTierComparisonRows(WidgetRef ref) {
  final config = ref.read(configServiceProvider);
  final prices = config.subscriptionPrices;
  final previewLimits = config.dailyPreviewLimits;
  final pdfLimits = config.pdfExportLimits;
  final examGenTiers = config.examGenerationAllowedTiers;
  final bulkPdfTiers = config.bulkPdfExportAllowedTiers;
  final aiDiagramsTiers = config.aiDiagramsAllowedTiers;

  const fallbackTeacherSeats = <String, dynamic>{
    'free': 5, 'basic': 10, 'standard': 20, 'elite': 100,
  };
  const fallbackLessonStorage = <String, dynamic>{
    'free': 10, 'basic': 20, 'standard': 50, 'elite': -1,
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
      previewLimit: _tierLimitText(previewLimits['free'], fallback: 0),
      pdfExports: _tierLimitText(pdfLimits['free'], fallback: 1),
      vaultPublishing: false,
      watermark: true,
      teacherSeats: _tierLimitText(teacherSeatLimits['free'], fallback: 5),
      lessonStorage: _tierLimitText(lessonStorageLimits['free'], fallback: 10),
      aiDiagrams: aiDiagramsTiers.contains('free'),
      examGeneration: examGenTiers.contains('free'),
      bulkPdfExport: bulkPdfTiers.contains('free'),
    ),
    _TierComparisonRow(
      tier: 'basic',
      name: 'Basic',
      price: _tierPrice(prices['basic'], AppConstants.basicPlanPriceNaira),
      previewLimit: _tierLimitText(previewLimits['basic'], fallback: 10),
      pdfExports: _tierLimitText(pdfLimits['basic'], fallback: 3),
      vaultPublishing: false,
      watermark: false,
      teacherSeats: _tierLimitText(teacherSeatLimits['basic'], fallback: 10),
      lessonStorage: _tierLimitText(lessonStorageLimits['basic'], fallback: 20),
      aiDiagrams: aiDiagramsTiers.contains('basic'),
      examGeneration: examGenTiers.contains('basic'),
      bulkPdfExport: bulkPdfTiers.contains('basic'),
    ),
    _TierComparisonRow(
      tier: 'standard',
      name: 'Standard',
      price: _tierPrice(prices['standard'], AppConstants.standardPlanPriceNaira),
      previewLimit: _tierLimitText(previewLimits['standard'], fallback: 10),
      pdfExports: _tierLimitText(pdfLimits['standard'], fallback: 5),
      vaultPublishing: true,
      watermark: false,
      teacherSeats: _tierLimitText(teacherSeatLimits['standard'], fallback: 20),
      lessonStorage: _tierLimitText(lessonStorageLimits['standard'], fallback: 50),
      aiDiagrams: aiDiagramsTiers.contains('standard'),
      examGeneration: examGenTiers.contains('standard'),
      bulkPdfExport: bulkPdfTiers.contains('standard'),
    ),
    _TierComparisonRow(
      tier: 'elite',
      name: 'Elite',
      price: _tierPrice(prices['elite'], AppConstants.elitePlanPriceNaira),
      previewLimit: _tierLimitText(previewLimits['elite'], fallback: -1),
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

      for (final payment in pendingPayments) {
        final confirmed = await paymentService.verifyPayment(
          payment.transactionReference,
        );
        if (!confirmed || !mounted) {
          continue;
        }
        await _confirmAndShowCode(
          context,
          ref,
          paymentService,
          payment.transactionReference,
          payment.plan,
          schoolId,
        );
        break;
      }
    } catch (_) {}
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
    if (!context.mounted) return;
    showInfoToast(
      context: context,
      message: 'Waiting for payment confirmation...',
    );

    for (int i = 0; i < 10; i++) {
      final confirmed = await paymentService.verifyPayment(reference);
      if (confirmed) {
        if (!context.mounted) return;
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

      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
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
    final bool isWide = screenWidth >= 1100;

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
        title: Text(
          'Compare Plans',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
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
                      // Comparison table + order summary
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 8,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: _buildComparisonTable(
                                  cs,
                                  textTheme,
                                  _tiers,
                                  selectedTier: selectedTier,
                                  onSelectTier: (tier) =>
                                      _selectedTierNotifier.value = tier,
                                  onChoosePlan: (tier) {
                                    _selectedPlanTier = tier;
                                    _selectedTierNotifier.value = tier;
                                    setState(() {});
                                  },
                                  availableWidth: (screenWidth -
                                          48 // padding
                                          - 32 // gap
                                      ) *
                                      (8 / 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 32),
                            Expanded(
                              flex: 4,
                              child: _buildOrderSummary(
                                context,
                                cs,
                                textTheme,
                                _planDefFromTierRow(selectedTierRow),
                              ),
                            ),
                          ],
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: _buildComparisonTable(
                                cs,
                                textTheme,
                                _tiers,
                                selectedTier: selectedTier,
                                onSelectTier: (tier) =>
                                    _selectedTierNotifier.value = tier,
                                onChoosePlan: (tier) {
                                  _selectedPlanTier = tier;
                                  _selectedTierNotifier.value = tier;
                                  setState(() {});
                                },
                                availableWidth:
                                    screenWidth - 48, // 24 left + 24 right
                              ),
                            ),
                            const SizedBox(height: 20),
                            _buildOrderSummary(
                              context,
                              cs,
                              textTheme,
                              _planDefFromTierRow(selectedTierRow),
                            ),
                          ],
                        ),
                      if (_isProcessing)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Center(child: CircularProgressIndicator()),
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
  final String previewLimit;
  final String pdfExports;
  final bool vaultPublishing;
  final bool watermark;
  final String teacherSeats;
  final String lessonStorage;
  final bool aiDiagrams;
  final bool examGeneration;
  final bool bulkPdfExport;

  String get dailyPreviews => previewLimit;

  const _TierComparisonRow({
    required this.tier,
    required this.name,
    required this.price,
    required this.previewLimit,
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
