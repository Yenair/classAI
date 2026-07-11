// lib/core/widgets/upgrade_request_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/core/services/upgrade_request_service.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';

/// Shows a centered dialog for teacher users explaining Elite benefits
/// and offering a "Request Upgrade" button that calls the edge function.
///
/// For admin users, the caller should still navigate to `/payment` directly.
Future<void> showUpgradeRequestDialog(
  BuildContext context,
  WidgetRef ref, {
  String requestedTier = 'elite',
}) async {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Center(
      child: SingleChildScrollView(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 28,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Icon ──
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      size: 32,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Heading ──
                  Text(
                    'Upgrade Required',
                    style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Elite benefits summary ──
                  _buildBenefitItem(
                    cs, tt,
                    Icons.auto_awesome_rounded,
                    'Unlimited AI-generated lessons and exams',
                  ),
                  const SizedBox(height: 8),
                  _buildBenefitItem(
                    cs, tt,
                    Icons.download_rounded,
                    'Download and share lesson notes & exam questions as PDFs',
                  ),
                  const SizedBox(height: 8),
                  _buildBenefitItem(
                    cs, tt,
                    Icons.speed_rounded,
                    'Priority AI generation and diagram generation',
                  ),
                  const SizedBox(height: 8),
                  _buildBenefitItem(
                    cs, tt,
                    Icons.sync_rounded,
                    'Advanced school-wide sync and teacher management',
                  ),
                  const SizedBox(height: 8),
                  _buildBenefitItem(
                    cs, tt,
                    Icons.people_rounded,
                    'More seats for teachers and unlimited storage',
                  ),
                  const SizedBox(height: 24),

                  // ── Request Upgrade button ──
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await _sendUpgradeRequest(
                          context,
                          ref,
                          requestedTier,
                        );
                      },
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Request Upgrade'),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Close button ──
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _buildBenefitItem(
  ColorScheme cs,
  TextTheme tt,
  IconData icon,
  String text,
) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: cs.primary),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );
}

Future<void> _sendUpgradeRequest(
  BuildContext context,
  WidgetRef ref,
  String requestedTier,
) async {
  final authService = ref.read(authServiceProvider);
  final authState = ref.read(authProvider);
  final accessToken = authService.currentJwt;

  // Check role — this is a UI guard only; the edge function independently
  // validates the JWT and looks up the teacher's real role.
  final role = authState.currentTeacher?.role;
  if (role == 'admin') {
    // Admin should navigate to payment instead
    if (context.mounted) {
      context.push('/payment');
    }
    return;
  }

  if (accessToken == null || accessToken.isEmpty) {
    if (context.mounted) {
      _showCenteredToast(
        context,
        'Not authenticated. Please log in again.',
      );
    }
    return;
  }

  final service = UpgradeRequestService();
  final result = await service.sendUpgradeRequest(
    accessToken: accessToken,
    requestedTier: requestedTier,
  );

  if (!context.mounted) return;

  if (result.success) {
    _showCenteredToast(
      context,
      'Request sent! Your school admin will review it shortly.',
    );
  } else if (result.alreadyRequested) {
    _showCenteredToast(
      context,
      'Your request has already been sent to the school admin.',
    );
  } else {
    // Failed — distinct message for genuine failures
    _showCenteredToast(
      context,
      result.message ??
          "Couldn't send your request — check your connection and try again.",
    );
  }
}

void _showCenteredToast(BuildContext context, String message) {
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: cs.tertiaryContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.tertiary.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: cs.onSurface.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: DefaultTextStyle(
            style: tt.bodyMedium?.copyWith(
              color: cs.onTertiaryContainer,
              fontWeight: FontWeight.w500,
            ) ?? const TextStyle(),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(seconds: 3), () {
    entry.remove();
  });
}
