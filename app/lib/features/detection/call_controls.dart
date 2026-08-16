import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../services/call_service.dart';

class CallControls extends ConsumerWidget {
  const CallControls({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callServiceProvider);
    final isThisCall = callState.sessionId == sessionId;
    final status = isThisCall ? callState.status : CallStatus.idle;
    final requiresMicrophoneSettings =
        isThisCall && callState.requiresMicrophoneSettings;
    final service = ref.read(callServiceProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 180,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _isInProgress(status)
                  ? AppColors.danger
                  : AppColors.navy,
            ),
            onPressed: switch (status) {
              CallStatus.connecting || CallStatus.reconnecting => null,
              CallStatus.active => service.endCall,
              CallStatus.disconnected =>
                requiresMicrophoneSettings
                    ? service.openMicrophoneSettings
                    : service.retryCall,
              CallStatus.idle => () => service.startCall(sessionId),
            },
            icon: Icon(switch (status) {
              CallStatus.active => Icons.call_end,
              CallStatus.disconnected =>
                requiresMicrophoneSettings ? Icons.settings : Icons.refresh,
              CallStatus.connecting || CallStatus.reconnecting => Icons.sync,
              CallStatus.idle => Icons.call,
            }),
            label: Text(switch (status) {
              CallStatus.connecting => '연결 중',
              CallStatus.active => '전화 끊기',
              CallStatus.reconnecting => '재연결 중',
              CallStatus.disconnected =>
                requiresMicrophoneSettings ? '권한 설정' : '다시 연결',
              CallStatus.idle => '전화 연결',
            }),
          ),
        ),
        if (status == CallStatus.active ||
            status == CallStatus.reconnecting ||
            status == CallStatus.disconnected) ...[
          const SizedBox(height: 6),
          Text(
            switch (status) {
              CallStatus.active => '통화 중',
              CallStatus.reconnecting =>
                '연결 끊김 · 자동 재연결 ${callState.retryAttempt}/3',
              CallStatus.disconnected =>
                callState.message ?? '연결 끊김 · 다시 시도해 주세요.',
              _ => '',
            },
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: status == CallStatus.active
                  ? AppColors.success
                  : AppColors.danger,
            ),
          ),
        ],
      ],
    );
  }

  bool _isInProgress(CallStatus status) =>
      status == CallStatus.connecting ||
      status == CallStatus.active ||
      status == CallStatus.reconnecting;
}
