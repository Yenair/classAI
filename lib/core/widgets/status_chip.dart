import 'package:flutter/material.dart';

/// Shared status visual language for ClassAI.
///
/// Status chips always pair an icon with a text label so meaning is never
/// conveyed by color alone. The palette deliberately avoids the exam-type
/// colors (indigo / teal) so type coding and lifecycle/status coding never
/// collide.
///
/// Foregrounds are chosen per chip via [statusForegroundFor] (black or white
/// text) instead of raw theme roles, so the same chip stays readable in both
/// light and dark themes.

// ── Lesson/exam lifecycle statuses ────────────────────────────────────────
const kStatusDraftColor = Color(0xFF9E9E9E); // grey
const kStatusGeneratedColor = Color(0xFF2196F3); // blue
const kStatusUnlockedColor = Color(0xFF7E57C2); // purple
const kStatusCompletedColor = Color(0xFF4CAF50); // green
const kStatusNeedsSyncColor = Color(0xFFFFA000); // amber

// ── Scheme of work statuses ───────────────────────────────────────────────
const kSchemeStatusPendingColor = Color(0xFFFFA000); // amber
const kSchemeStatusApprovedColor = Color(0xFF4CAF50); // green
const kSchemeStatusRejectedColor = Color(0xFFE53935); // red
const kSchemeStatusDraftColor = Color(0xFF9E9E9E); // grey

// ── Scheme-linked marker ──────────────────────────────────────────────────
const kSchemeLinkedColor = Color(0xFF795548); // brown

/// Returns a black or white foreground that contrasts with [background].
Color statusForegroundFor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black;

/// A small icon + text status chip. [color] is the chip background; the
/// foreground is derived for contrast via [statusForegroundFor], so the chip
/// is never color-only.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.dense = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = statusForegroundFor(color);
    final textStyle =
        (dense ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
            ?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 10,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(dense ? 6 : 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: dense ? 12 : 14, color: foreground),
          const SizedBox(width: 4),
          Text(label, style: textStyle),
        ],
      ),
    );
  }
}

/// Status chip for an exam row. Exams have no separate completed/generated
/// display today, so a row is either Draft or Unlocked.
StatusChip examRowStatusChip({required bool unlocked}) => unlocked
    ? const StatusChip(
        label: 'Unlocked',
        icon: Icons.auto_awesome_rounded,
        color: kStatusUnlockedColor,
      )
    : const StatusChip(
        label: 'Draft',
        icon: Icons.edit_note_rounded,
        color: kStatusDraftColor,
      );

/// Status chip for a lesson row. Priority:
/// Completed > Unlocked > Generated > Draft.
StatusChip lessonRowStatusChip({
  required bool completed,
  required bool unlocked,
  required bool generated,
}) {
  if (completed) {
    return const StatusChip(
      label: 'Completed',
      icon: Icons.check_circle_rounded,
      color: kStatusCompletedColor,
    );
  }
  if (unlocked) {
    return const StatusChip(
      label: 'Unlocked',
      icon: Icons.auto_awesome_rounded,
      color: kStatusUnlockedColor,
    );
  }
  if (generated) {
    return const StatusChip(
      label: 'Generated',
      icon: Icons.lock_open_rounded,
      color: kStatusGeneratedColor,
    );
  }
  return const StatusChip(
    label: 'Draft',
    icon: Icons.edit_note_rounded,
    color: kStatusDraftColor,
  );
}

/// Status chip for a lesson's stored status string ('completed' / 'generated'
/// / anything else = Draft). Used by the Scheme admin's linked-lesson rows.
StatusChip lessonStatusChipFor(String? status) {
  switch (status?.trim().toLowerCase()) {
    case 'completed':
      return const StatusChip(
        label: 'Completed',
        icon: Icons.check_circle_rounded,
        color: kStatusCompletedColor,
      );
    case 'generated':
      return const StatusChip(
        label: 'Generated',
        icon: Icons.lock_open_rounded,
        color: kStatusGeneratedColor,
      );
    default:
      return const StatusChip(
        label: 'Draft',
        icon: Icons.edit_note_rounded,
        color: kStatusDraftColor,
      );
  }
}

/// Status chip for a scheme-of-work status string. Unknown or empty statuses
/// render as a grey chip labelled [fallbackLabel] (e.g. 'No Scheme').
StatusChip schemeStatusChip(String? status, {String fallbackLabel = 'Draft'}) {
  switch (status?.trim().toLowerCase()) {
    case 'pending':
      return const StatusChip(
        label: 'Pending',
        icon: Icons.schedule_rounded,
        color: kSchemeStatusPendingColor,
      );
    case 'approved':
      return const StatusChip(
        label: 'Approved',
        icon: Icons.verified_rounded,
        color: kSchemeStatusApprovedColor,
      );
    case 'rejected':
      return const StatusChip(
        label: 'Rejected',
        icon: Icons.cancel_rounded,
        color: kSchemeStatusRejectedColor,
      );
    default:
      return StatusChip(
        label: fallbackLabel,
        icon: Icons.edit_note_rounded,
        color: kSchemeStatusDraftColor,
      );
  }
}

/// Small brown "Linked" marker shown next to the status chip on rows that are
/// linked to a scheme of work.
StatusChip schemeLinkedChip() => const StatusChip(
      label: 'Linked',
      icon: Icons.link_rounded,
      color: kSchemeLinkedColor,
      dense: true,
    );
