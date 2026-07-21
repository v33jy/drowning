import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/severity.dart';
import '../../../core/widgets/status_chip.dart';

/// FAB-triggered legend explaining marker and heatmap colors.
void showLegendPopup(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('범례'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('드론 마커', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          const Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              StatusChip(severity: Severity.ok, label: '정상'),
              StatusChip(severity: Severity.warning, label: '주의(배터리 40% 이하)'),
              StatusChip(severity: Severity.danger, label: '위험(배터리 20% 이하)'),
              StatusChip(severity: Severity.offline, label: 'Offline(신호 상실)'),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('전파 히트맵', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            '진할수록 신호가 강하게 잡힌 구역, 옅을수록 아직 스캔되지 않은 구역입니다.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    ),
  );
}
