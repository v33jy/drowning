import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// label + tabular-numeric value (+ optional unit). Used anywhere a drone
/// metric is displayed — drone card, drone detail, detection log detail —
/// so number alignment stays consistent everywhere.
class MetricRow extends StatelessWidget {
  const MetricRow({
    super.key,
    required this.label,
    required this.value,
    this.unit,
  });

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        RichText(
          text: TextSpan(
            text: value,
            style: AppTypography.numeric(color: AppColors.textPrimary),
            children: unit == null
                ? null
                : [
                    TextSpan(
                      text: ' $unit',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
          ),
        ),
      ],
    );
  }
}
