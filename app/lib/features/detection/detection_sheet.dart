import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/video_thumbnail.dart';
import '../../models/detection_event.dart';
import '../control/providers/video_frame_provider.dart';
import 'providers/detection_log_provider.dart';

/// Result returned when the sheet closes, so [ControlScreen] knows whether
/// to immediately open the next queued detection.
enum DetectionOutcome { rescued, falseAlarm, minimized }

Future<DetectionOutcome?> showDetectionSheet(
  BuildContext context,
  DetectionEvent event,
) {
  return showDialog<DetectionOutcome>(
    context: context,
    barrierDismissible: false, // 실수로 바깥 탭해서 닫히면 안 되는 화면
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: DetectionSheet(event: event),
        ),
      ),
    ),
  );
}

class DetectionSheet extends ConsumerStatefulWidget {
  const DetectionSheet({super.key, required this.event});

  final DetectionEvent event;

  @override
  ConsumerState<DetectionSheet> createState() => _DetectionSheetState();
}

class _DetectionSheetState extends ConsumerState<DetectionSheet> {
  void _resolve(DetectionOutcome outcome) {
    final status = switch (outcome) {
      DetectionOutcome.rescued => DetectionStatus.rescued,
      DetectionOutcome.falseAlarm => DetectionStatus.falseAlarm,
      DetectionOutcome.minimized => DetectionStatus.pending,
    };
    ref.read(detectionLogProvider.notifier).resolve(widget.event.detectionId, status);
    Navigator.of(context).pop(outcome);
  }

  Future<void> _confirmFalseAlarm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('오탐으로 처리할까요?'),
        content: const Text('이 탐지를 오탐으로 표시하면 목록에서 사라지고 되돌릴 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('오탐 처리'),
          ),
        ],
      ),
    );
    if (confirmed == true) _resolve(DetectionOutcome.falseAlarm);
  }

  void _minimize() {
    Navigator.of(context).pop(DetectionOutcome.minimized);
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final elapsed = _elapsedLabel(event.timestamp);
    final frameB64 = ref.watch(videoFrameProvider.select((m) => m[event.droneId]));

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '드론 #${event.droneId} · Cell ${event.cellId}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(elapsed, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(width: AppSpacing.sm),
              // 오탐 처리/최소화 — both occasional, secondary actions, so
              // they live here as small icons instead of full buttons
              // competing with the one real decision in the body (구조
              // 완료). 오탐 처리 still confirms via dialog before doing
              // anything irreversible — only the entry point shrank.
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _confirmFalseAlarm,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.flag_outlined, size: 18, color: AppColors.danger),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _minimize,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.remove_circle_outline, size: 18, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'RSS ${event.rssDbm.toStringAsFixed(1)} dBm',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          // 고정 높이 사용: 16:9 AspectRatio는 가로로 넓은 landscape 태블릿에서
          // 폭 기준으로 너무 큰 높이를 요구해 시트 예산(maxHeightFraction)을
          // 넘기고 버튼들을 스크롤 없인 안 보이는 위치로 밀어낸다.
          VideoThumbnail(frameB64: frameB64, height: 140),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.success),
              onPressed: () => _resolve(DetectionOutcome.rescued),
              child: const Text('구조 완료'),
            ),
          ),
        ],
      ),
    );
  }
}

String _elapsedLabel(double timestampSeconds) {
  final then = DateTime.fromMillisecondsSinceEpoch((timestampSeconds * 1000).round());
  final diff = DateTime.now().difference(then);
  if (diff.inSeconds < 60) return '${diff.inSeconds}초 전';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  return '${diff.inHours}시간 전';
}
