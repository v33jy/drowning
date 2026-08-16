import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/heatmap_cell.dart';
import '../providers/heatmap_provider.dart';
import '../providers/grid_provider.dart';
import 'search_area_guidance.dart';
import 'search_panel_components.dart';
import 'video_review_section.dart';

class LiveSearchAreaDetail extends ConsumerWidget {
  const LiveSearchAreaDetail({
    required this.cellId,
    required this.onClose,
    super.key,
  });

  final String cellId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cell = ref.watch(
      heatmapProvider.select(
        (cells) => cells[cellId] ?? HeatmapCell.unscanned(cellId),
      ),
    );
    final locationLabel = locationLabelForCell(
      cellId: cellId,
      labels: ref.watch(gridLocationLabelProvider),
      grid: ref.watch(gridDefProvider),
    );
    return SearchAreaDetailSheet(
      cell: cell,
      locationLabel: locationLabel,
      onClose: onClose,
      videoReview: VideoReviewSection(cellId: cellId),
    );
  }
}

class SearchAreaDetailSheet extends StatelessWidget {
  const SearchAreaDetailSheet({
    required this.cell,
    this.locationLabel = '위치 정보 없음',
    this.onClose,
    this.videoReview,
    super.key,
  });

  final HeatmapCell cell;
  final String locationLabel;
  final VoidCallback? onClose;
  final Widget? videoReview;

  @override
  Widget build(BuildContext context) {
    final guidance = SearchAreaGuidance.fromCell(cell);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SearchStatusHeader(
            status: guidance.statusLabel,
            statusColor: guidance.color,
            locationLabel: locationLabel,
            trailing: onClose == null
                ? null
                : IconButton(
                    tooltip: '닫기',
                    onPressed: onClose,
                    icon: const Icon(Icons.close, size: 20),
                  ),
          ),
          SearchActionSummary(action: guidance.action, reason: guidance.reason),
          const SizedBox(height: AppSpacing.lg),
          _InfoRow(label: '최근 확인', value: formatLastChecked(cell.lastUpdated)),
          const SizedBox(height: AppSpacing.lg),
          Text('확인 영상', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          videoReview ?? const Text('이 구역에 보존된 영상이 없습니다.'),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(width: AppSpacing.sm),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
