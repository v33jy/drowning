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
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Row(
      children: [
        Container(width: 8, height: 8, color: statusColor),
        const SizedBox(width: AppSpacing.sm),
        Text(
          status,
          style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            locationLabel,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ),
        ?trailing,
      ],
    ),
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        action,
        style: const TextStyle(
          fontSize: 20,
          height: 1.35,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(reason),
    ],
  );
}
