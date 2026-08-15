import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../models/heatmap_cell.dart';
import '../providers/heatmap_provider.dart';
import 'search_area_guidance.dart';
import 'video_review_section.dart';

Future<void> showSearchAreaDetailSheet(BuildContext context, String cellId) =>
    AppBottomSheet.show<void>(
      context: context,
      maxHeightFraction: 0.62,
      builder: (_) => _LiveSearchAreaDetail(cellId: cellId),
    );

class _LiveSearchAreaDetail extends ConsumerWidget {
  const _LiveSearchAreaDetail({required this.cellId});

  final String cellId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cell = ref.watch(
      heatmapProvider.select(
        (cells) => cells[cellId] ?? HeatmapCell.unscanned(cellId),
      ),
    );
    return SearchAreaDetailSheet(
      cell: cell,
      videoReview: VideoReviewSection(cellId: cellId),
    );
  }
}

class SearchAreaDetailSheet extends StatelessWidget {
  const SearchAreaDetailSheet({
    required this.cell,
    this.videoReview,
    super.key,
  });

  final HeatmapCell cell;
  final Widget? videoReview;

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
          const SizedBox(height: AppSpacing.lg),
          Text('당시 영상', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          videoReview ?? const Text('이 구역에 보존된 영상이 없습니다.'),
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
