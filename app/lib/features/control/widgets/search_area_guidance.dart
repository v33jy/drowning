import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/heatmap_cell.dart';

@immutable
class SearchAreaGuidance {
  const SearchAreaGuidance({
    required this.statusLabel,
    required this.reason,
    required this.action,
    required this.color,
    required this.icon,
  });

  final String statusLabel;
  final String reason;
  final String action;
  final Color color;
  final IconData icon;

  factory SearchAreaGuidance.fromCell(HeatmapCell cell) {
    final status = _statusPresentation[cell.status]!;
    final reasonCode = _reasonStatuses[cell.statusReason] == cell.status
        ? cell.statusReason
        : status.defaultReasonCode;
    return SearchAreaGuidance(
      statusLabel: status.label,
      reason: _reasonLabels[reasonCode]!,
      action: status.action,
      color: status.color,
      icon: status.icon,
    );
  }
}

class _StatusPresentation {
  const _StatusPresentation({
    required this.label,
    required this.defaultReasonCode,
    required this.action,
    required this.color,
    required this.icon,
  });

  final String label;
  final String defaultReasonCode;
  final String action;
  final Color color;
  final IconData icon;
}

const _reasonLabels = <String, String>{
  'no_measurements': '아직 수색 판단에 필요한 측정이 없습니다.',
  'insufficient_repeated_signal': '신호를 수집했지만 반복 확인 기준에 도달하지 않았습니다.',
  'repeated_strong_signal': '구조 신호가 같은 구역에서 반복 확인되었습니다.',
};

const _reasonStatuses = <String, SearchAreaStatus>{
  'no_measurements': SearchAreaStatus.unscanned,
  'insufficient_repeated_signal': SearchAreaStatus.scanning,
  'repeated_strong_signal': SearchAreaStatus.needsRecheck,
};

const _statusPresentation = <SearchAreaStatus, _StatusPresentation>{
  SearchAreaStatus.unscanned: _StatusPresentation(
    label: '미확인',
    defaultReasonCode: 'no_measurements',
    action: '드론으로 이 구역을 우선 확인하세요.',
    color: AppColors.offline,
    icon: Icons.help_outline,
  ),
  SearchAreaStatus.scanning: _StatusPresentation(
    label: '확인 중',
    defaultReasonCode: 'insufficient_repeated_signal',
    action: '같은 경로를 유지하며 추가 측정하세요.',
    color: AppColors.primary,
    icon: Icons.radar,
  ),
  SearchAreaStatus.needsRecheck: _StatusPresentation(
    label: '재확인 필요',
    defaultReasonCode: 'repeated_strong_signal',
    action: '주변 구역을 재수색하고 현장 확인을 검토하세요.',
    color: AppColors.warning,
    icon: Icons.warning_amber_outlined,
  ),
};

String formatLastChecked(DateTime? timestamp, {DateTime? now}) {
  if (timestamp == null) return '확인 기록 없음';
  final current = (now ?? DateTime.now()).toUtc();
  final elapsed = current.difference(timestamp.toUtc());
  if (elapsed.isNegative || elapsed.inMinutes < 1) return '방금 전';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}분 전';
  if (elapsed.inDays < 1) return '${elapsed.inHours}시간 전';
  return '${elapsed.inDays}일 전';
}
