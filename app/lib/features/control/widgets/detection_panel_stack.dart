import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/detection_event.dart';
import '../../../models/grid_cell.dart';
import '../../detection/detection_sheet.dart';
import '../providers/grid_provider.dart';
import 'floating_map_panel.dart';

class DetectionPanelStack extends StatelessWidget {
  const DetectionPanelStack({
    required this.maxHeight,
    required this.activeDetection,
    required this.pendingDetections,
    required this.locationLabels,
    required this.gridDefinition,
    required this.onDetectionTap,
    required this.onOutcome,
    required this.onResize,
    super.key,
  });

  static const _noticeSlotHeight = 60.0;

  final double maxHeight;
  final DetectionEvent activeDetection;
  final List<DetectionEvent> pendingDetections;
  final Map<String, String> locationLabels;
  final Map<String, CellBounds> gridDefinition;
  final ValueChanged<DetectionEvent> onDetectionTap;
  final ValueChanged<DetectionOutcome> onOutcome;
  final ValueChanged<DragUpdateDetails> onResize;

  @override
  Widget build(BuildContext context) {
    final previous = pendingDetections.reversed
        .where((event) => event.detectionId != activeDetection.detectionId)
        .take(2)
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingMapPanel(
          maxHeight: maxHeight - previous.length * _noticeSlotHeight,
          onResize: onResize,
          child: DetectionSheet(
            key: ValueKey(activeDetection.detectionId),
            event: activeDetection,
            showCloseButton: true,
            onOutcome: onOutcome,
          ),
        ),
        for (final event in previous) ...[
          const SizedBox(height: AppSpacing.sm),
          _DetectionNoticeCard(
            event: event,
            locationLabel: locationLabelForCell(
              cellId: event.cellId,
              labels: locationLabels,
              grid: gridDefinition,
            ),
            onTap: () => onDetectionTap(event),
          ),
        ],
      ],
    );
  }
}

class _DetectionNoticeCard extends StatelessWidget {
  const _DetectionNoticeCard({
    required this.event,
    required this.locationLabel,
    required this.onTap,
  });

  final DetectionEvent event;
  final String locationLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.border),
      borderRadius: BorderRadius.circular(2),
    ),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: AppColors.warning,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                locationLabel,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              _notificationAge(event.timestamp),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    ),
  );
}

String _notificationAge(double timestampSeconds) {
  final timestamp = DateTime.fromMillisecondsSinceEpoch(
    (timestampSeconds * 1000).round(),
  );
  final elapsed = DateTime.now().difference(timestamp);
  if (elapsed.inMinutes < 1) return '방금 전';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}분 전';
  return '${elapsed.inHours}시간 전';
}
