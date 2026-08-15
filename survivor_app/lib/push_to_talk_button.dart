import 'package:flutter/material.dart';

class SurvivorPushToTalkButton extends StatefulWidget {
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
  State<SurvivorPushToTalkButton> createState() =>
      _SurvivorPushToTalkButtonState();
}

class _SurvivorPushToTalkButtonState extends State<SurvivorPushToTalkButton> {
  bool _holding = false;

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
      label: label,
      child: GestureDetector(
        onLongPressStart: (_) => _startTransmitting(),
        onLongPressEnd: (_) => _stopTransmitting(),
        onLongPressCancel: _stopTransmitting,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          decoration: BoxDecoration(
            color: widget.isTransmitting
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isTransmitting ? Icons.mic : Icons.mic_off,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
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
