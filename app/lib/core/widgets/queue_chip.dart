import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// "미확인 탐지 N건" — shown on the control screen when a detection is
/// queued behind an open sheet, or when a sheet has been minimized.
/// Renders nothing when [count] is 0. Presentational only; the caller
/// supplies the count from whichever detection-queue provider it watches.
class QueueChip extends StatelessWidget {
  const QueueChip({super.key, required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    // Pending detections carry Severity.warning everywhere else in the app
    // (기록 screen, log icons) — filling this in AppColors.primary instead
    // read as an arbitrary brand-blue badge with no relation to that
    // vocabulary. Amber + white (same "solid fill, white label" idiom as the
    // navy menu button/selected chips) reads as an actual alert.
    return Material(
      color: AppColors.warning,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.priority_high, size: 14, color: Colors.white),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '미확인 탐지 $count건',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
