import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

class SearchStatusHeader extends StatelessWidget {
  const SearchStatusHeader({
    required this.status,
    required this.statusColor,
    required this.locationLabel,
    this.trailing,
    super.key,
  });

  final String status;
  final Color statusColor;
  final String locationLabel;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: statusColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.35),
                    blurRadius: 5,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Text(
              status,
              style: TextStyle(
                color: statusColor,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text(
          locationLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            height: 1.3,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      ?trailing,
    ],
  );
}

class SearchActionSummary extends StatelessWidget {
  const SearchActionSummary({
    required this.action,
    required this.reason,
    super.key,
  });

  final String action;
  final String reason;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
    decoration: BoxDecoration(
      color: AppColors.navy.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.navy.withValues(alpha: 0.12)),
    ),
    child: Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Container(
            width: 3,
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                action,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 21,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                reason,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
