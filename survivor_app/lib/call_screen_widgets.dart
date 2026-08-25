import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'call_models.dart';

class BrandSplashScreen extends StatelessWidget {
  const BrandSplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Color(0xFFF2F7FF),
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BrandLogo(size: 64),
            SizedBox(height: 12),
            Text(
              'DROWNING',
              style: TextStyle(
                color: Color(0xFF052B57),
                fontSize: 19,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.8,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BrandLogo extends StatelessWidget {
  const _BrandLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.22),
    child: SvgPicture.asset(
      'assets/images/drowning-drone-logo.svg',
      width: size,
      height: size,
    ),
  );
}

class LiquidBackground extends StatelessWidget {
  const LiquidBackground({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF6FAFF), Color(0xFFDCEBFF), Color(0xFFF2F7FF)],
      ),
    ),
  );
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x180C3B72),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: child,
      ),
    ),
  );
}

class AppBrandHeader extends StatelessWidget {
  const AppBrandHeader({super.key});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const _BrandLogo(size: 44),
      const SizedBox(width: 12),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '요구조자 긴급 통신',
              style: TextStyle(
                color: Color(0xFF10294F),
                fontSize: 19,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
            SizedBox(height: 1),
            Text(
              'EMERGENCY COMMUNICATION',
              style: TextStyle(
                color: Color(0xFF607590),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.05,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class CallStatusCard extends StatelessWidget {
  const CallStatusCard({
    super.key,
    required this.phase,
    required this.retryAttempt,
    required this.maxReconnectAttempts,
  });

  final CallPhase phase;
  final int retryAttempt;
  final int maxReconnectAttempts;

  @override
  Widget build(BuildContext context) {
    final copy = switch (phase) {
      CallPhase.waiting => ('통화 대기 중', '구조대가 주변 신호를 확인하고 있습니다'),
      CallPhase.connecting => ('통화 연결 중', '구조대와 안전한 통신 채널을 연결합니다'),
      CallPhase.active => ('구조대와 연결됨', '침착하게 현재 상황을 알려주세요'),
      CallPhase.reconnecting => (
        '통화 재연결 중',
        '자동 재연결 $retryAttempt/$maxReconnectAttempts',
      ),
      CallPhase.disconnected => ('통화 연결 끊김', '아래 버튼을 눌러 다시 연결해주세요'),
    };
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      child: Column(
        children: [
          Text(
            copy.$1,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF10294F),
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            copy.$2,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF5C708A),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class SafetyGuideCard extends StatelessWidget {
  const SafetyGuideCard({super.key});

  @override
  Widget build(BuildContext context) => const GlassPanel(
    child: Row(
      children: [
        Icon(Icons.info_outline_rounded, color: Color(0xFF1A5AB2)),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            '휴대전화를 가까이 두고 안전한 곳에서 구조대의 연락을 기다려주세요.',
            style: TextStyle(
              color: Color(0xFF405571),
              height: 1.45,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class NormalCallControl extends StatelessWidget {
  const NormalCallControl({
    super.key,
    required this.isMuted,
    required this.onToggleMute,
  });

  final bool isMuted;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(58),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: isMuted
              ? const Color(0xFFFFE8EB)
              : const Color(0xFFE4EEFF),
          foregroundColor: isMuted
              ? const Color(0xFFB72F42)
              : const Color(0xFF164194),
        ),
        onPressed: onToggleMute,
        icon: Icon(isMuted ? Icons.mic_off_rounded : Icons.mic_rounded),
        label: Text(
          isMuted ? '음소거 해제' : '마이크 음소거',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        isMuted ? '내 목소리가 전달되지 않습니다' : '양방향 음성 통화 중입니다',
        style: const TextStyle(
          color: Color(0xFF405571),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}
