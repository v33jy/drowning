import '../../../core/widgets/severity.dart';
import '../../../models/detection_event.dart';
import '../../detection/providers/detection_log_provider.dart';

enum LogEntryType { detection, activity, batteryLow, signalLost }

enum LogActivityKind {
  searchStarted,
  areaNeedsRecheck,
  callConnecting,
  callConnected,
  callEnded,
  detectionResolved,
}

/// Unified row for the 기록 screen (구 "탐지 이력" + "알림 센터"). Detections
/// carry their original event + resolution status; drone health alerts are
/// plain text entries derived from telemetry transitions.
class LogEntry {
  const LogEntry({
    required this.type,
    required this.droneId,
    required this.timestamp,
    required this.title,
    required this.severity,
    this.detectionEvent,
    this.status,
    this.activityKind,
  });

  final LogEntryType type;
  final int droneId;
  final DateTime timestamp;
  final String title;
  final Severity severity;
  final DetectionEvent? detectionEvent;
  final DetectionStatus? status;
  final LogActivityKind? activityKind;

  /// "조치 필요" 필터에 실제로 의미가 있는 건 탐지뿐이다 — 대기 중이면 조치가
  /// 필요하다는 뜻이고, 처리되면 끝이다. 배터리/신호 경고는 그런 액션 상태가
  /// 없는 정보성 알림이라 읽음/안읽음을 흉내 내지 않는다 — "전체"에서만 보인다.
  bool get isUnresolved =>
      type == LogEntryType.detection && status == DetectionStatus.pending;
}
