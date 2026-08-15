import 'package:control_app/core/widgets/severity.dart';
import 'package:control_app/features/log/models/log_entry.dart';
import 'package:control_app/features/log/providers/call_activity_recorder.dart';
import 'package:control_app/services/call_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LogEntry createEntry({
    required LogActivityKind kind,
    required String title,
    required Severity severity,
    required DateTime timestamp,
    CallActivityDetails? callDetails,
  }) => LogEntry(
    type: LogEntryType.activity,
    activityKind: kind,
    droneId: 1,
    timestamp: timestamp,
    title: title,
    severity: severity,
    callDetails: callDetails,
  );

  test('records call start and end timestamps with duration', () {
    final recorder = CallActivityRecorder();
    final startedAt = DateTime(2026, 8, 15, 14, 32, 10);
    final endedAt = startedAt.add(const Duration(minutes: 3, seconds: 12));

    final started = recorder.recordTransition(
      previous: const CallState(CallStatus.connecting, sessionId: 'call-1'),
      next: const CallState(CallStatus.active, sessionId: 'call-1'),
      timestamp: startedAt,
      createEntry: createEntry,
    );
    final ended = recorder.recordTransition(
      previous: const CallState(CallStatus.active, sessionId: 'call-1'),
      next: const CallState(CallStatus.idle),
      timestamp: endedAt,
      createEntry: createEntry,
    );

    expect(started.single.title, '음성 통화 시작');
    expect(started.single.callDetails?.startedAt, startedAt);
    expect(ended.single.title, '음성 통화 종료');
    expect(ended.single.callDetails?.startedAt, startedAt);
    expect(ended.single.callDetails?.endedAt, endedAt);
    expect(
      ended.single.callDetails?.duration,
      const Duration(minutes: 3, seconds: 12),
    );
  });

  test('failed connection is recorded without a fabricated call time', () {
    final recorder = CallActivityRecorder();
    final ended = recorder.recordTransition(
      previous: const CallState(CallStatus.connecting, sessionId: 'call-1'),
      next: const CallState(CallStatus.idle),
      timestamp: DateTime(2026, 8, 15),
      createEntry: createEntry,
    );

    expect(ended.single.title, '음성 연결 종료');
    expect(ended.single.callDetails, isNull);
  });
}
