import 'package:flutter/material.dart';

/// User-facing vocabulary shared by the map, candidate popup, and history.
abstract final class SearchAreaCopy {
  static const veryWeakSignalLabel = '신호 매우 약함';
  static const weakSignalLabel = '신호 약함';
  static const moderateSignalLabel = '신호 보통';
  static const strongSignalLabel = '신호 강함';

  static const unsearchedLabel = '미수색';
  static const unsearchedReason = '아직 신호가 측정되지 않은 구역입니다.';
  static const unsearchedAction = '해당 구역을 수색 경로에 포함하세요.';

  static const candidateLabel = '요구조자 후보';
  static const candidateReason = '강한 신호가 반복적으로 측정되어 확인이 필요한 구역입니다.';
  static const candidateLogReason = '강한 신호가 반복적으로 측정되어 확인이 필요한 구역으로 분류되었습니다.';
  static const candidateAction = '번호 순서대로 방문해 현장 영상을 확인하세요.';

  static const falseAlarmLabel = '오탐';
  static const falseAlarmReason = '현장 영상 확인 결과 요구조자가 없는 구역입니다.';
  static const falseAlarmAction = '다음 후보 구역으로 이동하세요.';

  static const survivorFoundLabel = '요구조자 발견';
  static const survivorFoundReason = '현장 영상 확인 결과 요구조자가 발견되었습니다.';
  static const survivorFoundAction = '영상과 전화 연결을 유지하며 구조를 진행하세요.';
}

abstract final class SearchAreaColors {
  static const veryWeak = Color(0xFF1565C0);
  static const weak = Color(0xFF00838F);
  static const moderate = Color(0xFF2E7D32);
  static const strong = Color(0xFFFBC02D);
  static const candidate = Color(0xFFF57C00);
  static const falseAlarm = Color(0xFF7A838C);
  static const survivorFound = Color(0xFFD32F2F);
}

enum SignalStrengthBand { veryWeak, weak, moderate, strong }

class SignalStrengthPresentation {
  const SignalStrengthPresentation({
    required this.band,
    required this.label,
    required this.reason,
    required this.action,
    required this.color,
  });

  final SignalStrengthBand band;
  final String label;
  final String reason;
  final String action;
  final Color color;
}

SignalStrengthPresentation signalStrengthPresentation(double signal) =>
    switch (signal) {
      < -85 => const SignalStrengthPresentation(
        band: SignalStrengthBand.veryWeak,
        label: SearchAreaCopy.veryWeakSignalLabel,
        reason: '주변에서 매우 약한 신호가 측정되었습니다.',
        action: '현재 경로대로 수색을 계속하세요.',
        color: SearchAreaColors.veryWeak,
      ),
      < -75 => const SignalStrengthPresentation(
        band: SignalStrengthBand.weak,
        label: SearchAreaCopy.weakSignalLabel,
        reason: '주변에서 약한 신호가 측정되었습니다.',
        action: '주변 구역을 함께 확인하세요.',
        color: SearchAreaColors.weak,
      ),
      < -65 => const SignalStrengthPresentation(
        band: SignalStrengthBand.moderate,
        label: SearchAreaCopy.moderateSignalLabel,
        reason: '주변에서 보통 세기의 신호가 측정되었습니다.',
        action: '추가로 신호를 수집해 후보 여부를 판단하세요.',
        color: SearchAreaColors.moderate,
      ),
      _ => const SignalStrengthPresentation(
        band: SignalStrengthBand.strong,
        label: SearchAreaCopy.strongSignalLabel,
        reason: '주변에서 강한 신호가 측정되었습니다.',
        action: '주변 구역과 비교하여 요구조자 후보 여부를 확인하세요.',
        color: SearchAreaColors.strong,
      ),
    };
