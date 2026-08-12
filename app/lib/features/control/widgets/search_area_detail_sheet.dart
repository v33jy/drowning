import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../models/heatmap_cell.dart';

Future<void> showSearchAreaDetailSheet(
  BuildContext context,
  HeatmapCell cell,
) => AppBottomSheet.show<void>(
  context: context,
  maxHeightFraction: 0.62,
  builder: (_) => SearchAreaDetailSheet(cell: cell),
);

class SearchAreaDetailSheet extends StatelessWidget {
  const SearchAreaDetailSheet({required this.cell, super.key});

  final HeatmapCell cell;

  @override
  Widget build(BuildContext context) {
    final guidance = SearchAreaGuidance.fromCell(cell);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '수색 구역 ${cell.cellId}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _AreaStatusBadge(guidance: guidance),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _GuidancePanel(guidance: guidance),
          const SizedBox(height: AppSpacing.lg),
          Text('확인 정보', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          _InfoRow(label: '최근 확인', value: formatLastChecked(cell.lastUpdated)),
          _InfoRow(label: '측정 횟수', value: '${cell.sampleCount}회'),
          _InfoRow(label: '확인 드론', value: '${cell.droneCount}대'),
          if (cell.needsRecheck)
            _InfoRow(label: '반복 확인', value: '${cell.strongSignalCount}회'),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '이 정보는 수색 판단을 지원하며 구조 대상자의 위치를 확정하지 않습니다.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class SearchAreaGuidance {
  const SearchAreaGuidance({
    required this.statusLabel,
    required this.reason,
    required this.action,
    required this.color,
    required this.icon,
  });

  final String statusLabel;
  final String reason;
  final String action;
  final Color color;
  final IconData icon;

  factory SearchAreaGuidance.fromCell(HeatmapCell cell) =>
      switch (cell.status) {
        SearchAreaStatus.unscanned => const SearchAreaGuidance(
          statusLabel: '미확인',
          reason: '아직 수색 판단에 필요한 측정이 없습니다.',
          action: '드론으로 이 구역을 우선 확인하세요.',
          color: AppColors.offline,
          icon: Icons.help_outline,
        ),
        SearchAreaStatus.scanning => const SearchAreaGuidance(
          statusLabel: '확인 중',
          reason: '신호를 수집했지만 반복 확인 기준에 도달하지 않았습니다.',
          action: '같은 경로를 유지하며 추가 측정하세요.',
          color: AppColors.primary,
          icon: Icons.radar,
        ),
        SearchAreaStatus.needsRecheck => const SearchAreaGuidance(
          statusLabel: '재확인 필요',
          reason: '구조 신호가 같은 구역에서 반복 확인되었습니다.',
          action: '주변 구역을 재수색하고 현장 확인을 검토하세요.',
          color: AppColors.warning,
          icon: Icons.warning_amber_outlined,
        ),
      };
}

String formatLastChecked(DateTime? timestamp, {DateTime? now}) {
  if (timestamp == null) return '확인 기록 없음';
  final current = (now ?? DateTime.now()).toUtc();
  final elapsed = current.difference(timestamp.toUtc());
  if (elapsed.isNegative || elapsed.inMinutes < 1) return '방금 전';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}분 전';
  if (elapsed.inDays < 1) return '${elapsed.inHours}시간 전';
  return '${elapsed.inDays}일 전';
}

class _AreaStatusBadge extends StatelessWidget {
  const _AreaStatusBadge({required this.guidance});

  final SearchAreaGuidance guidance;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: guidance.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    child: Text(
      guidance.statusLabel,
      style: TextStyle(color: guidance.color, fontWeight: FontWeight.w700),
    ),
  );
}

class _GuidancePanel extends StatelessWidget {
  const _GuidancePanel({required this.guidance});

  final SearchAreaGuidance guidance;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: guidance.color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: guidance.color.withValues(alpha: 0.25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(guidance.icon, color: guidance.color),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(guidance.reason),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '권장 조치: ${guidance.action}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
