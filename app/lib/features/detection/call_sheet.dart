import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../services/voip_service.dart';

enum _CallPhase { connecting, connected }

/// VoIP call sheet — pushed on top of the Detection Sheet (not replacing
/// it), so popping this one returns to the detection sheet automatically.
class CallSheet extends StatefulWidget {
  const CallSheet({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<CallSheet> createState() => _CallSheetState();
}

class _CallSheetState extends State<CallSheet> {
  final _voip = VoipService();
  _CallPhase _phase = _CallPhase.connecting;
  bool _muted = false;
  DateTime? _connectedAt;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _voip.startCall(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _phase = _CallPhase.connected;
      _connectedAt = DateTime.now();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(_connectedAt!));
    });
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _voip.setMuted(_muted);
  }

  Future<void> _end() async {
    _ticker?.cancel();
    await _voip.stopCall();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _voip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _phase == _CallPhase.connected;
    final minutes = _elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!connected) ...[
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('연결 중…', style: Theme.of(context).textTheme.bodyMedium),
          ] else ...[
            Text(
              '통화 중 · $minutes:$seconds',
              style: AppTypography.numeric(
                  color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RoundButton(
                icon: _muted ? Icons.mic_off : Icons.mic_none,
                label: _muted ? '음소거됨' : '음소거',
                onTap: _toggleMute,
              ),
              const SizedBox(width: AppSpacing.xxl),
              _RoundButton(
                icon: Icons.call_end,
                label: '종료',
                filled: true,
                color: AppColors.danger,
                onTap: _end,
              ),
              const SizedBox(width: AppSpacing.xxl),
              _RoundButton(
                icon: Icons.volume_up_outlined,
                label: '스피커',
                onTap: () {}, // 출력 라우팅은 플랫폼 오디오 세션 API 필요 — 시각적 자리만 확보
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.color = AppColors.textPrimary,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: filled ? color : AppColors.surface,
          shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(filled ? AppSpacing.lg : AppSpacing.md),
              child: Icon(icon, color: filled ? Colors.white : color, size: filled ? 26 : 22),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}
