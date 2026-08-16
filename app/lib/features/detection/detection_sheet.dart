import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/video_thumbnail.dart';
import '../../models/detection_event.dart';
import '../../services/call_service.dart';
import '../control/providers/video_frame_provider.dart';
import '../control/providers/grid_provider.dart';
import '../control/widgets/search_panel_components.dart';
import 'call_controls.dart';
import 'microphone_input_indicator.dart';
import 'providers/detection_log_provider.dart';
import 'push_to_talk_button.dart';

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
  const DetectionSheet({
    super.key,
    required this.event,
    this.onOutcome,
    this.showCloseButton = true,
  });

  final DetectionEvent event;
  final ValueChanged<DetectionOutcome>? onOutcome;
  final bool showCloseButton;

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
    final onOutcome = widget.onOutcome;
    if (onOutcome != null) {
      onOutcome(outcome);
    } else {
      Navigator.of(context).pop(outcome);
    }
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
    final onOutcome = widget.onOutcome;
    if (onOutcome != null) {
      onOutcome(DetectionOutcome.minimized);
    } else {
      Navigator.of(context).pop(DetectionOutcome.minimized);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final locationLabel = locationLabelForCell(
      cellId: event.cellId,
      labels: ref.watch(gridLocationLabelProvider),
      grid: ref.watch(gridDefProvider),
    );
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
          SearchStatusHeader(
            status: '재확인 필요',
            statusColor: AppColors.warning,
            locationLabel: locationLabel,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(elapsed, style: Theme.of(context).textTheme.labelSmall),
                IconButton(
                  tooltip: '오탐 처리',
                  onPressed: _confirmFalseAlarm,
                  icon: const Icon(
                    Icons.flag_outlined,
                    size: 18,
                    color: AppColors.danger,
                  ),
                ),
                if (widget.showCloseButton)
                  IconButton(
                    tooltip: '닫기',
                    onPressed: _minimize,
                    icon: Icon(
                      widget.onOutcome == null
                          ? Icons.remove_circle_outline
                          : Icons.close,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SearchActionSummary(
            action: '해당 위치를 저고도로 다시 통과하세요.',
            reason: '같은 위치에서 신호가 반복되어 추가 확인이 필요합니다.',
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('현장 영상', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          VideoThumbnail(frameB64: frameB64, height: videoHeight),
          const SizedBox(height: AppSpacing.md),
          Container(
            height: 40,
            decoration: const BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(color: AppColors.border),
              ),
            ),
            child: Row(
              children: [
                if (event.callSessionId != null) ...[
                  Expanded(
                    child: CallControls(sessionId: event.callSessionId!),
                  ),
                  const VerticalDivider(width: 1, indent: 9, endIndent: 9),
                  SizedBox(
                    width: 48,
                    child: Center(
                      child: PushToTalkButton(
                        enabled:
                            isThisCall && callState.status == CallStatus.active,
                        isTransmitting: callState.isTransmitting,
                        onTransmitStart: ref
                            .read(callServiceProvider.notifier)
                            .startTransmitting,
                        onTransmitEnd: ref
                            .read(callServiceProvider.notifier)
                            .stopTransmitting,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
              ],
            ),
          ),
          if (event.callSessionId != null &&
              isThisCall &&
              callState.status == CallStatus.disconnected) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              callState.message ?? '연결이 끊겼습니다. 다시 시도해 주세요.',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.danger),
            ),
          ],
          if (event.callSessionId != null && isThisCall) ...[
            if (callState.status == CallStatus.active) ...[
              const SizedBox(height: AppSpacing.xs),
              MicrophoneInputIndicator(
                status: callState.microphoneInputStatus,
                level: callState.microphoneLevel,
              ),
            ],
          ],
          SizedBox(
            width: double.infinity,
            height: 40,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                foregroundColor: AppColors.success,
                alignment: Alignment.centerLeft,
                shape: const RoundedRectangleBorder(),
              ),
              onPressed: () => _resolve(DetectionOutcome.rescued),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('구조 완료'),
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
