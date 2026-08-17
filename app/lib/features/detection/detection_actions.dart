import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../services/call_service.dart';
import 'call_controls.dart';
import 'microphone_input_indicator.dart';
import 'push_to_talk_button.dart';

class DetectionActions extends ConsumerWidget {
  const DetectionActions({
    required this.callSessionId,
    required this.onRescued,
    super.key,
  });

  final String? callSessionId;
  final VoidCallback onRescued;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionId = callSessionId;
    final callState = ref.watch(callServiceProvider);
    final isCurrentCall = callState.sessionId == sessionId;
    final isActive = isCurrentCall && callState.status == CallStatus.active;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sessionId != null) ...[
          _CallToolbar(
            sessionId: sessionId,
            isActive: isActive,
            isTransmitting: callState.isTransmitting,
          ),
          if (isCurrentCall && callState.status == CallStatus.disconnected) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              callState.message ?? '연결이 끊겼습니다. 다시 시도해 주세요.',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.danger),
            ),
          ],
          if (isActive) ...[
            const SizedBox(height: AppSpacing.xs),
            MicrophoneInputIndicator(
              status: callState.microphoneInputStatus,
              level: callState.microphoneLevel,
            ),
          ],
        ] else
          const _UnavailableCallToolbar(),
        _RescueCompleteButton(onPressed: onRescued),
      ],
    );
  }
}

class _UnavailableCallToolbar extends StatelessWidget {
  const _UnavailableCallToolbar();

  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    decoration: const BoxDecoration(
      border: Border.symmetric(horizontal: BorderSide(color: AppColors.border)),
    ),
  );
}

class _CallToolbar extends ConsumerWidget {
  const _CallToolbar({
    required this.sessionId,
    required this.isActive,
    required this.isTransmitting,
  });

  final String sessionId;
  final bool isActive;
  final bool isTransmitting;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    height: 40,
    decoration: const BoxDecoration(
      border: Border.symmetric(horizontal: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        Expanded(child: CallControls(sessionId: sessionId)),
        const VerticalDivider(width: 1, indent: 9, endIndent: 9),
        SizedBox(
          width: 48,
          child: Center(
            child: PushToTalkButton(
              enabled: isActive,
              isTransmitting: isTransmitting,
              onTransmitStart: ref
                  .read(callServiceProvider.notifier)
                  .startTransmitting,
              onTransmitEnd: ref
                  .read(callServiceProvider.notifier)
                  .stopTransmitting,
            ),
          ),
        ),
      ],
    ),
  );
}

class _RescueCompleteButton extends StatelessWidget {
  const _RescueCompleteButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
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
      onPressed: onPressed,
      icon: const Icon(Icons.check, size: 18),
      label: const Text('구조 완료'),
    ),
  );
}
