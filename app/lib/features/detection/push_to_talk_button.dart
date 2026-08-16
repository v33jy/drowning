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
    final label = widget.isTransmitting ? '음성 전달 중' : '누르고 말하기';
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
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: widget.isTransmitting
                ? AppColors.danger
                : widget.enabled
                ? AppColors.navy
                : Colors.transparent,
            shape: BoxShape.circle,
            border: widget.enabled || widget.isTransmitting
                ? null
                : Border.all(color: AppColors.border),
          ),
          child: Icon(
            widget.isTransmitting ? Icons.mic : Icons.mic_none,
            color: widget.enabled ? Colors.white : AppColors.textSecondary,
            size: 17,
          ),
        ),
      ),
    );
  }
}
