import 'package:flutter/material.dart';

class SurvivorPushToTalkButton extends StatelessWidget {
  const SurvivorPushToTalkButton({
    super.key,
    required this.isTransmitting,
    required this.onTransmitStart,
    required this.onTransmitEnd,
  });

  final bool isTransmitting;
  final VoidCallback onTransmitStart;
  final VoidCallback onTransmitEnd;

  @override
  Widget build(BuildContext context) {
    final label = isTransmitting ? '말하는 중 · 놓으면 음소거' : '길게 눌러 말하기';
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onLongPressStart: (_) => onTransmitStart(),
        onLongPressEnd: (_) => onTransmitEnd(),
        onLongPressCancel: onTransmitEnd,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          decoration: BoxDecoration(
            color: isTransmitting
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isTransmitting ? Icons.mic : Icons.mic_off,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
