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
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.isTransmitting
                  ? const [Color(0xFFFF6070), Color(0xFFC9263A)]
                  : const [Color(0xFF3479DA), Color(0xFF123D8E)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
            boxShadow: [
              BoxShadow(
                color:
                    (widget.isTransmitting
                            ? const Color(0xFFC9263A)
                            : const Color(0xFF164194))
                        .withValues(alpha: 0.28),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.isTransmitting
                      ? Icons.mic_rounded
                      : Icons.mic_none_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
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
