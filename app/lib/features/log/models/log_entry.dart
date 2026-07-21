import '../../../core/widgets/severity.dart';
import '../../../models/detection_event.dart';
import '../../detection/providers/detection_log_provider.dart';

enum LogEntryType { detection, batteryLow, signalLost }

/// Unified row for the 기록 screen (구 "탐지 이력" + "알림 센터"). Detections
/// carry their original event + resolution status; drone health alerts are
/// plain text entries derived from telemetry transitions.
class LogEntry {
  const LogEntry({
    required this.type,
    required this.timestamp,
    required this.title,
    required this.severity,
    this.detectionEvent,
    this.status,
  });

  final LogEntryType type;
  final DateTime timestamp;
  final String title;
  final Severity severity;
  final DetectionEvent? detectionEvent;
  final DetectionStatus? status;

  bool get isUnresolved => type == LogEntryType.detection
      ? status == DetectionStatus.pending
      : DateTime.now().difference(timestamp) < const Duration(minutes: 10);
}
