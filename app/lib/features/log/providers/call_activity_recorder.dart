import '../../../core/widgets/severity.dart';
import '../../../services/call_service.dart';
import '../models/log_entry.dart';

class CallActivityRecord {
  const CallActivityRecord({
    required this.kind,
    required this.title,
    required this.severity,
    required this.timestamp,
    this.details,
  });

  final LogActivityKind kind;
  final String title;
  final Severity severity;
  final DateTime timestamp;
  final CallActivityDetails? details;
}

/// Converts CallService state transitions into operator-facing history rows.
/// Active calls are tracked by session so their end event can retain the
/// actual start timestamp and duration.
class CallActivityRecorder {
  CallActivityDetails? _activeCall;

  List<CallActivityRecord> recordTransition({
    required CallState? previous,
    required CallState next,
    required DateTime timestamp,
  }) {
    if (previous?.status == next.status) return const [];

    switch (next.status) {
      case CallStatus.connecting:
        return [
          CallActivityRecord(
            kind: LogActivityKind.callConnecting,
            title: '음성 연결 시도',
            severity: Severity.warning,
            timestamp: timestamp,
          ),
        ];
      case CallStatus.active:
        final sessionId = next.sessionId;
        if (sessionId == null) return const [];
        if (_activeCall?.sessionId == sessionId) return const [];
        _activeCall = CallActivityDetails(
          sessionId: sessionId,
          startedAt: timestamp,
        );
        return [
          CallActivityRecord(
            kind: LogActivityKind.callConnected,
            title: '음성 통화 시작',
            severity: Severity.ok,
            timestamp: timestamp,
            details: _activeCall,
          ),
        ];
      case CallStatus.reconnecting:
        return [
          CallActivityRecord(
            kind: LogActivityKind.callConnecting,
            title: '음성 연결 끊김 · 자동 재연결 중',
            severity: Severity.warning,
            timestamp: timestamp,
          ),
        ];
      case CallStatus.disconnected:
        return [_endRecord(timestamp, failed: true)];
      case CallStatus.idle:
        if (previous == null || previous.status == CallStatus.idle) {
          return const [];
        }
        if (previous.status == CallStatus.disconnected) return const [];
        return [_endRecord(timestamp)];
    }
  }

  CallActivityRecord _endRecord(DateTime timestamp, {bool failed = false}) {
    final activeCall = _activeCall;
    _activeCall = null;
    final wasActive = activeCall != null;
    return CallActivityRecord(
      kind: LogActivityKind.callEnded,
      title: switch ((wasActive, failed)) {
        (true, true) => '음성 통화 종료 · 연결 실패',
        (true, false) => '음성 통화 종료',
        (false, true) => '음성 연결 실패 · 수동 재시도 필요',
        (false, false) => '음성 연결 종료',
      },
      severity: Severity.offline,
      timestamp: timestamp,
      details: activeCall?.ended(timestamp),
    );
  }
}
