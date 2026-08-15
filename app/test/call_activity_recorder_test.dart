import 'package:control_app/features/log/providers/call_activity_recorder.dart';
import 'package:control_app/services/call_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records call start and end timestamps with duration', () {
    final recorder = CallActivityRecorder();
    final startedAt = DateTime(2026, 8, 15, 14, 32, 10);
    final endedAt = startedAt.add(const Duration(minutes: 3, seconds: 12));

    final started = recorder.recordTransition(
      previous: const CallState(CallStatus.connecting, sessionId: 'call-1'),
      next: const CallState(CallStatus.active, sessionId: 'call-1'),
      timestamp: startedAt,
    );
    final ended = recorder.recordTransition(
      previous: const CallState(CallStatus.active, sessionId: 'call-1'),
      next: const CallState(CallStatus.idle),
      timestamp: endedAt,
    );

    expect(started.single.title, '음성 통화 시작');
    expect(started.single.details?.startedAt, startedAt);
    expect(ended.single.title, '음성 통화 종료');
    expect(ended.single.details?.startedAt, startedAt);
    expect(ended.single.details?.endedAt, endedAt);
    expect(
      ended.single.details?.duration,
      const Duration(minutes: 3, seconds: 12),
    );
  });

  test('failed connection is recorded without a fabricated call time', () {
    final recorder = CallActivityRecorder();
    final ended = recorder.recordTransition(
      previous: const CallState(CallStatus.connecting, sessionId: 'call-1'),
      next: const CallState(CallStatus.idle),
      timestamp: DateTime(2026, 8, 15),
    );

    expect(ended.single.title, '음성 연결 종료');
    expect(ended.single.details, isNull);
  });

  test('reconnection keeps the original call start time', () {
    final recorder = CallActivityRecorder();
    final startedAt = DateTime(2026, 8, 15, 23, 58);
    final reconnectedAt = startedAt.add(const Duration(minutes: 1));
    final endedAt = startedAt.add(const Duration(minutes: 4));

    recorder.recordTransition(
      previous: const CallState(CallStatus.connecting, sessionId: 'call-1'),
      next: const CallState(CallStatus.active, sessionId: 'call-1'),
      timestamp: startedAt,
    );
    recorder.recordTransition(
      previous: const CallState(CallStatus.active, sessionId: 'call-1'),
      next: const CallState(CallStatus.reconnecting, sessionId: 'call-1'),
      timestamp: startedAt.add(const Duration(seconds: 30)),
    );
    final reconnected = recorder.recordTransition(
      previous: const CallState(CallStatus.reconnecting, sessionId: 'call-1'),
      next: const CallState(CallStatus.active, sessionId: 'call-1'),
      timestamp: reconnectedAt,
    );
    final ended = recorder.recordTransition(
      previous: const CallState(CallStatus.active, sessionId: 'call-1'),
      next: const CallState(CallStatus.idle),
      timestamp: endedAt,
    );

    expect(reconnected, isEmpty);
    expect(ended.single.details?.startedAt, startedAt);
    expect(ended.single.details?.endedAt, endedAt);
  });
}
