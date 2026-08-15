import '../../../core/widgets/severity.dart';
import '../../../services/call_service.dart';
import '../models/log_entry.dart';

typedef ActivityEntryFactory =
    LogEntry Function({
      required LogActivityKind kind,
      required String title,
      required Severity severity,
      required DateTime timestamp,
      CallActivityDetails? callDetails,
    });

/// Converts CallService state transitions into operator-facing history rows.
/// Active calls are tracked by session so their end event can retain the
/// actual start timestamp and duration.
class CallActivityRecorder {
  CallActivityDetails? _activeCall;

  List<LogEntry> recordTransition({
    required CallState? previous,
    required CallState next,
    required DateTime timestamp,
    required ActivityEntryFactory createEntry,
  }) {
    if (previous?.status == next.status) return const [];

    switch (next.status) {
      case CallStatus.connecting:
        return [
          createEntry(
            kind: LogActivityKind.callConnecting,
            title: '음성 연결 시도',
            severity: Severity.warning,
            timestamp: timestamp,
          ),
        ];
      case CallStatus.active:
        final sessionId = next.sessionId;
        if (sessionId == null) return const [];
        _activeCall = CallActivityDetails(
          sessionId: sessionId,
          startedAt: timestamp,
        );
        return [
          createEntry(
            kind: LogActivityKind.callConnected,
            title: '음성 통화 시작',
            severity: Severity.ok,
            timestamp: timestamp,
            callDetails: _activeCall,
          ),
        ];
      case CallStatus.idle:
        if (previous == null || previous.status == CallStatus.idle) {
          return const [];
        }
        final activeCall = _activeCall;
        _activeCall = null;
        final details = activeCall == null
            ? null
            : CallActivityDetails(
                sessionId: activeCall.sessionId,
                startedAt: activeCall.startedAt,
                endedAt: timestamp,
              );
        return [
          createEntry(
            kind: LogActivityKind.callEnded,
            title: activeCall == null ? '음성 연결 종료' : '음성 통화 종료',
            severity: Severity.offline,
            timestamp: timestamp,
            callDetails: details,
          ),
        ];
    }
  }
}
