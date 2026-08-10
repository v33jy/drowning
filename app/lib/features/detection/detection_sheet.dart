import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/video_thumbnail.dart';
import '../../models/detection_event.dart';
import '../../services/call_service.dart';
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
    builder: (context) {
      final screenSize = MediaQuery.sizeOf(context);
      return Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: math.min(760.0, screenSize.width * 0.88),
            maxWidth: 760,
            maxHeight: screenSize.height * 0.9,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: DetectionSheet(event: event),
          ),
        ),
      );
    },
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
    ref.read(callServiceProvider.notifier).endCall();
    final status = switch (outcome) {
      DetectionOutcome.rescued => DetectionStatus.rescued,
      DetectionOutcome.falseAlarm => DetectionStatus.falseAlarm,
      DetectionOutcome.minimized => DetectionStatus.pending,
    };
    ref
        .read(detectionLogProvider.notifier)
        .resolve(widget.event.detectionId, status);
    Navigator.of(context).pop(outcome);
  }

  Future<void> _confirmFalseAlarm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('오탐으로 처리할까요?'),
        content: const Text('이 탐지를 오탐으로 표시하면 목록에서 사라지고 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
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
    ref.read(callServiceProvider.notifier).endCall();
    Navigator.of(context).pop(DetectionOutcome.minimized);
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final elapsed = _elapsedLabel(event.timestamp);
    final frameB64 = ref.watch(
      videoFrameProvider.select((m) => m[event.droneId]),
    );
    final callState = ref.watch(callServiceProvider);
    final isThisCall = callState.sessionId == event.callSessionId;
    final videoHeight = math.min(
      340.0,
      MediaQuery.sizeOf(context).height * 0.46,
    );

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
                  child: Icon(
                    Icons.flag_outlined,
                    size: 18,
                    color: AppColors.danger,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _minimize,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.remove_circle_outline,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
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
          // Keep the actions visible while giving the live feed most of the dialog.
          VideoThumbnail(frameB64: frameB64, height: videoHeight),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.center,
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.center,
              children: [
                if (event.callSessionId != null)
                  SizedBox(
                    width: 180,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: isThisCall
                            ? AppColors.danger
                            : AppColors.navy,
                      ),
                      onPressed:
                          callState.status == CallStatus.connecting &&
                              isThisCall
                          ? null
                          : () {
                              if (isThisCall) {
                                ref
                                    .read(callServiceProvider.notifier)
                                    .endCall();
                              } else {
                                ref
                                    .read(callServiceProvider.notifier)
                                    .startCall(event.callSessionId!);
                              }
                            },
                      icon: Icon(isThisCall ? Icons.call_end : Icons.call),
                      label: Text(
                        isThisCall
                            ? callState.status == CallStatus.connecting
                                  ? '연결 중'
                                  : '전화 끊기'
                            : '전화 연결',
                      ),
                    ),
                  ),
                SizedBox(
                  width: 180,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                    ),
                    onPressed: () => _resolve(DetectionOutcome.rescued),
                    child: const Text('구조 완료'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _elapsedLabel(double timestampSeconds) {
  final then = DateTime.fromMillisecondsSinceEpoch(
    (timestampSeconds * 1000).round(),
  );
  final diff = DateTime.now().difference(then);
  if (diff.inSeconds < 60) return '${diff.inSeconds}초 전';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  return '${diff.inHours}시간 전';
}
