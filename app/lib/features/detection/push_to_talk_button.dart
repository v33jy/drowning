import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class PushToTalkButton extends StatefulWidget {
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
  State<PushToTalkButton> createState() => _PushToTalkButtonState();
}

class _PushToTalkButtonState extends State<PushToTalkButton> {
  bool _holding = false;

  @override
  void didUpdateWidget(PushToTalkButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) _stopTransmitting();
  }

  @override
  void dispose() {
    _stopTransmitting();
    super.dispose();
  }

  void _startTransmitting() {
    if (_holding) return;
    _holding = true;
    widget.onTransmitStart();
  }

  void _stopTransmitting() {
    if (!_holding) return;
    _holding = false;
    widget.onTransmitEnd();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.isTransmitting ? '말하는 중 · 놓으면 음소거' : '길게 눌러 말하기';
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: label,
      child: GestureDetector(
        onLongPressStart: widget.enabled ? (_) => _startTransmitting() : null,
        onLongPressEnd: widget.enabled ? (_) => _stopTransmitting() : null,
        onLongPressCancel: widget.enabled ? _stopTransmitting : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 220,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: widget.isTransmitting
                ? AppColors.danger
                : widget.enabled
                ? AppColors.navy
                : Colors.grey.shade400,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.isTransmitting ? Icons.mic : Icons.mic_off,
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
