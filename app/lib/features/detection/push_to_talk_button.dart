import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class PushToTalkButton extends StatelessWidget {
  const PushToTalkButton({
    super.key,
    required this.enabled,
    required this.isTransmitting,
    required this.onTransmitStart,
    required this.onTransmitEnd,
  });

  final bool enabled;
  final bool isTransmitting;
  final VoidCallback onTransmitStart;
  final VoidCallback onTransmitEnd;

  @override
  Widget build(BuildContext context) {
    final label = isTransmitting ? '말하는 중 · 놓으면 음소거' : '길게 눌러 말하기';
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onLongPressStart: enabled ? (_) => onTransmitStart() : null,
        onLongPressEnd: enabled ? (_) => onTransmitEnd() : null,
        onLongPressCancel: enabled ? onTransmitEnd : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 220,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: isTransmitting
                ? AppColors.danger
                : enabled
                ? AppColors.navy
                : Colors.grey.shade400,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isTransmitting ? Icons.mic : Icons.mic_off,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
