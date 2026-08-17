import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/call_service.dart';

class MicrophoneInputIndicator extends StatelessWidget {
  const MicrophoneInputIndicator({
    super.key,
    required this.status,
    required this.level,
  });

  final MicrophoneInputStatus status;
  final double level;

  @override
  Widget build(BuildContext context) {
    if (status == MicrophoneInputStatus.idle) return const SizedBox.shrink();

    final color = switch (status) {
      MicrophoneInputStatus.detected => AppColors.success,
      MicrophoneInputStatus.silent ||
      MicrophoneInputStatus.unavailable => AppColors.danger,
      MicrophoneInputStatus.checking => AppColors.textSecondary,
      MicrophoneInputStatus.idle => Colors.transparent,
    };
    final label = switch (status) {
      MicrophoneInputStatus.detected => '마이크 입력 감지됨',
      MicrophoneInputStatus.silent => '마이크 소리가 감지되지 않습니다',
      MicrophoneInputStatus.unavailable => '마이크 입력 상태를 확인할 수 없습니다',
      MicrophoneInputStatus.checking => '마이크 입력 확인 중',
      MicrophoneInputStatus.idle => '',
    };
    final activeBars = status == MicrophoneInputStatus.detected
        ? (level.clamp(0.0, 1.0) * 5).ceil().clamp(1, 5)
        : 0;

    return Semantics(
      label: label,
      liveRegion:
          status == MicrophoneInputStatus.silent ||
          status == MicrophoneInputStatus.unavailable,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(5, (index) {
              return Container(
                width: 6,
                height: 6 + (index * 3),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: index < activeBars ? color : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
