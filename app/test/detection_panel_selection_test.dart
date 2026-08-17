import 'package:control_app/features/control/detection_panel_selection.dart';
import 'package:control_app/models/detection_event.dart';
import 'package:control_app/services/call_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const first = DetectionEvent(
    droneId: 1,
    cellId: 'A0',
    rssDbm: -60,
    timestamp: 1,
    detectionId: 'first',
    callSessionId: 'call-1',
  );
  const latest = DetectionEvent(
    droneId: 1,
    cellId: 'A1',
    rssDbm: -55,
    timestamp: 2,
    detectionId: 'latest',
    callSessionId: 'call-2',
  );

  test('keeps the detection with an active call visible', () {
    final selected = selectDetectionForDisplay(
      pendingDetections: const [first, latest],
      callState: const CallState(CallStatus.active, sessionId: 'call-1'),
    );

    expect(selected.detectionId, 'first');
  });

  test('does not hide an active call when another notice is selected', () {
    final selected = selectDetectionForDisplay(
      pendingDetections: const [first, latest],
      callState: const CallState(CallStatus.active, sessionId: 'call-1'),
      preferredDetection: latest,
    );

    expect(selected.detectionId, 'first');
  });

  test('keeps connecting and reconnecting calls accessible', () {
    for (final status in [CallStatus.connecting, CallStatus.reconnecting]) {
      final selected = selectDetectionForDisplay(
        pendingDetections: const [first, latest],
        callState: CallState(status, sessionId: 'call-1'),
      );

      expect(selected.detectionId, 'first');
    }
  });

  test('promotes the latest detection when no call is in progress', () {
    final selected = selectDetectionForDisplay(
      pendingDetections: const [first, latest],
      callState: const CallState(CallStatus.idle),
    );

    expect(selected.detectionId, 'latest');
  });
}
