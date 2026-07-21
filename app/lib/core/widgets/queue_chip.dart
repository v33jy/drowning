import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// "미확인 탐지 N건" — shown on the control screen when a detection is
/// queued behind an active call, or when a sheet has been minimized.
/// Renders nothing when [count] is 0. Presentational only; the caller
/// supplies the count from whichever detection-queue provider it watches.
class QueueChip extends StatelessWidget {
  const QueueChip({super.key, required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Material(
      color: AppColors.primary,
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
              const Icon(Icons.priority_high, size: 14, color: AppColors.primaryInk),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '미확인 탐지 $count건',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
