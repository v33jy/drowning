import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../services/call_service.dart';
import 'microphone_input_indicator.dart';

class DetectionActions extends ConsumerStatefulWidget {
  const DetectionActions({
    required this.callSessionId,
    required this.onFalseAlarm,
    required this.onRescued,
    super.key,
  });

  final String? callSessionId;
  final VoidCallback onFalseAlarm;
  final VoidCallback onRescued;

  @override
  ConsumerState<DetectionActions> createState() => _DetectionActionsState();
}

class _DetectionActionsState extends ConsumerState<DetectionActions> {
  bool _pushToTalk = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callServiceProvider);
    final service = ref.read(callServiceProvider.notifier);
    final sessionId = widget.callSessionId;
    final status = state.sessionId == sessionId
        ? state.status
        : CallStatus.idle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('요구조자 전화', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        _CallSurface(
          child: sessionId == null
              ? const _StateLabel('통화 연결 정보 없음', AppColors.textSecondary)
              : _callContent(sessionId, status, state, service),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                ),
                onPressed: widget.onFalseAlarm,
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('오탐 처리'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                ),
                onPressed: widget.onRescued,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('구조 완료'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _callContent(
    String sessionId,
    CallStatus status,
    CallState state,
    CallService service,
  ) => switch (status) {
    CallStatus.idle => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StateLabel('통화 대기', AppColors.textSecondary),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          key: const Key('connect-survivor-call'),
          onPressed: () => service.startCall(sessionId),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.navy,
            minimumSize: const Size.fromHeight(44),
          ),
          child: const Text('전화 연결'),
        ),
      ],
    ),
    CallStatus.connecting || CallStatus.reconnecting => SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            status == CallStatus.reconnecting
                ? '재연결 ${state.retryAttempt}/3'
                : '연결 중…',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
    CallStatus.active => _activeCall(state, service),
    CallStatus.disconnected => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StateLabel('통화 종료됨', AppColors.textSecondary),
        if (state.message != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            state.message!,
            style: const TextStyle(color: AppColors.danger, fontSize: 12),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          key: const Key('reconnect-survivor-call'),
          onPressed: state.requiresMicrophoneSettings
              ? service.openMicrophoneSettings
              : service.retryCall,
          icon: Icon(
            state.requiresMicrophoneSettings ? Icons.settings : Icons.refresh,
          ),
          label: Text(state.requiresMicrophoneSettings ? '권한 설정' : '다시 전화하기'),
        ),
      ],
    ),
  };

  Widget _activeCall(CallState state, CallService service) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const _StateLabel('통화 중', AppColors.success),
          const Spacer(),
          FilledButton.icon(
            onPressed: service.endCall,
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            icon: const Icon(Icons.call_end_rounded, size: 17),
            label: const Text('통화 종료'),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      SegmentedButton<bool>(
        key: const Key('voice-mode-selector'),
        segments: const [
          ButtonSegment(
            value: false,
            label: Text('음성 전달'),
            icon: Icon(Icons.mic_rounded, size: 17),
          ),
          ButtonSegment(
            value: true,
            label: Text('눌러서 말하기'),
            icon: Icon(Icons.touch_app_rounded, size: 17),
          ),
        ],
        selected: {_pushToTalk},
        onSelectionChanged: (selection) {
          setState(() => _pushToTalk = selection.first);
          if (_pushToTalk) {
            service.stopTransmitting();
          } else {
            service.startTransmitting();
          }
        },
        showSelectedIcon: false,
      ),
      const SizedBox(height: AppSpacing.sm),
      if (!_pushToTalk)
        Container(
          key: const Key('continuous-voice-active'),
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
          ),
          child: const Text(
            '음성 전달 중',
            style: TextStyle(
              color: AppColors.success,
              fontWeight: FontWeight.w800,
            ),
          ),
        )
      else
        GestureDetector(
          key: const Key('push-to-talk'),
          onTapDown: (_) => service.startTransmitting(),
          onTapUp: (_) => service.stopTransmitting(),
          onTapCancel: service.stopTransmitting,
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: state.isTransmitting ? AppColors.primary : AppColors.navy,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              state.isTransmitting ? '말하는 중' : '눌러서 말하기',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      const SizedBox(height: AppSpacing.xs),
      MicrophoneInputIndicator(
        status: state.microphoneInputStatus,
        level: state.microphoneLevel,
      ),
    ],
  );
}

class _CallSurface extends StatelessWidget {
  const _CallSurface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}

class _StateLabel extends StatelessWidget {
  const _StateLabel(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 7),
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );
}
