import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/detection_event.dart';
import '../../control/data/ws_client.dart';
import '../../control/providers/ws_providers.dart';

enum DetectionStatus { pending, rescued, falseAlarm }

class DetectionLogEntry {
  const DetectionLogEntry({required this.event, required this.status});

  final DetectionEvent event;
  final DetectionStatus status;

  DetectionLogEntry copyWith({DetectionStatus? status}) =>
      DetectionLogEntry(event: event, status: status ?? this.status);
}

/// Single source of truth for every detection ever received — the pending
/// queue (Detection Sheet / QueueChip) and the 기록 screen's 전체/미확인
/// tabs are both just filtered views over this one list, not separate state.
class DetectionLogNotifier extends Notifier<List<DetectionLogEntry>> {
  @override
  List<DetectionLogEntry> build() {
    final client = ref.read(wsClientProvider);
    final sub = client.messageStream.listen(_onMessage);
    ref.onDispose(sub.cancel);
    return [];
  }

  void _onMessage(WsMessage msg) {
    if (msg.type != 'detection') return;
    final event = DetectionEvent.fromJson(msg.data as Map<String, dynamic>);
    state = [...state, DetectionLogEntry(event: event, status: DetectionStatus.pending)];
  }

  /// Resolves the entry matching [sessionId] — 구조 완료/오탐 처리 결과 반영.
  void resolve(String sessionId, DetectionStatus status) {
    state = [
      for (final e in state)
        if (e.event.voipSessionId == sessionId) e.copyWith(status: status) else e,
    ];
  }
}

final detectionLogProvider =
    NotifierProvider<DetectionLogNotifier, List<DetectionLogEntry>>(DetectionLogNotifier.new);

/// Pending entries only, in arrival order — what used to be a separate queue
/// provider. Derived, not duplicated state.
final pendingDetectionQueueProvider = Provider<List<DetectionEvent>>((ref) {
  final log = ref.watch(detectionLogProvider);
  return [
    for (final e in log)
      if (e.status == DetectionStatus.pending) e.event,
  ];
});
