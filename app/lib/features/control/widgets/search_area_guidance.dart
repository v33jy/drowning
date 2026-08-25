import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/heatmap_cell.dart';
import '../../../models/search_area_presentation.dart';

@immutable
class SearchAreaGuidance {
  const SearchAreaGuidance({
    required this.statusLabel,
    required this.reason,
    required this.action,
    required this.color,
  });

  final String statusLabel;
  final String reason;
  final String action;
  final Color color;

  factory SearchAreaGuidance.fromCell(HeatmapCell cell) {
    if (cell.status == SearchAreaStatus.scanning) {
      final presentation = signalStrengthPresentation(
        cell.rssDbm ?? cell.latestRssDbm ?? -100,
      );
      return SearchAreaGuidance(
        statusLabel: presentation.label,
        reason: presentation.reason,
        action: presentation.action,
        color: presentation.color,
      );
    }
    final status = _statusPresentation[cell.status]!;
    final reasonCode = _reasonStatuses[cell.statusReason] == cell.status
        ? cell.statusReason
        : status.defaultReasonCode;
    return SearchAreaGuidance(
      statusLabel: status.label,
      reason: _reasonLabels[reasonCode]!,
      action: status.action,
      color: status.color,
    );
  }
}

class _StatusPresentation {
  const _StatusPresentation({
    required this.label,
    required this.defaultReasonCode,
    required this.action,
    required this.color,
  });

  final String label;
  final String defaultReasonCode;
  final String action;
  final Color color;
}

const _reasonLabels = <String, String>{
  'no_measurements': SearchAreaCopy.unsearchedReason,
  'insufficient_repeated_signal': '신호를 수집했지만 반복 확인 기준에 도달하지 않았습니다.',
  'repeated_strong_signal': SearchAreaCopy.candidateReason,
  'operator_false_alarm': SearchAreaCopy.falseAlarmReason,
  'operator_survivor_confirmed': SearchAreaCopy.survivorFoundReason,
};

const _reasonStatuses = <String, SearchAreaStatus>{
  'no_measurements': SearchAreaStatus.unscanned,
  'insufficient_repeated_signal': SearchAreaStatus.scanning,
  'repeated_strong_signal': SearchAreaStatus.needsRecheck,
  'operator_false_alarm': SearchAreaStatus.cleared,
  'operator_survivor_confirmed': SearchAreaStatus.confirmed,
};

const _statusPresentation = <SearchAreaStatus, _StatusPresentation>{
  SearchAreaStatus.unscanned: _StatusPresentation(
    label: SearchAreaCopy.unsearchedLabel,
    defaultReasonCode: 'no_measurements',
    action: SearchAreaCopy.unsearchedAction,
    color: AppColors.offline,
  ),
  SearchAreaStatus.scanning: _StatusPresentation(
    label: SearchAreaCopy.veryWeakSignalLabel,
    defaultReasonCode: 'insufficient_repeated_signal',
    action: '현재 경로대로 수색을 계속하세요.',
    color: SearchAreaColors.veryWeak,
  ),
  SearchAreaStatus.needsRecheck: _StatusPresentation(
    label: SearchAreaCopy.candidateLabel,
    defaultReasonCode: 'repeated_strong_signal',
    action: SearchAreaCopy.candidateAction,
    color: SearchAreaColors.candidate,
  ),
  SearchAreaStatus.cleared: _StatusPresentation(
    label: SearchAreaCopy.falseAlarmLabel,
    defaultReasonCode: 'operator_false_alarm',
    action: SearchAreaCopy.falseAlarmAction,
    color: AppColors.textSecondary,
  ),
  SearchAreaStatus.confirmed: _StatusPresentation(
    label: SearchAreaCopy.survivorFoundLabel,
    defaultReasonCode: 'operator_survivor_confirmed',
    action: SearchAreaCopy.survivorFoundAction,
    color: AppColors.danger,
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
