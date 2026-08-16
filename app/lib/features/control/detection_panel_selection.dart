import '../../models/detection_event.dart';
import '../../services/call_service.dart';

/// Chooses which pending detection remains open when a new alert arrives.
///
/// A call in progress takes precedence so its hang-up and PTT controls never
/// become inaccessible behind newer notifications.
DetectionEvent selectDetectionForDisplay({
  required List<DetectionEvent> pendingDetections,
  required CallState callState,
  DetectionEvent? preferredDetection,
}) {
  assert(pendingDetections.isNotEmpty);
  if (_isCallInProgress(callState.status) && callState.sessionId != null) {
    for (final event in pendingDetections.reversed) {
      if (event.callSessionId == callState.sessionId) return event;
    }
  }
  return preferredDetection ?? pendingDetections.last;
}

bool _isCallInProgress(CallStatus status) =>
    status == CallStatus.connecting ||
    status == CallStatus.active ||
    status == CallStatus.reconnecting;
