import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/detection_event.dart';
import '../../control/data/ws_client.dart';
import '../../control/providers/ws_providers.dart';

/// FIFO queue of detection events awaiting a decision — front of the list
/// is whichever one is (or will be) shown as the active Detection Sheet.
/// Data plumbing only; the gating rules (구조 완료/오탐 처리, minimize-to-chip)
/// are built out fully in the Detection Bottom Sheet step.
class DetectionQueueNotifier extends Notifier<List<DetectionEvent>> {
  @override
  List<DetectionEvent> build() {
    final client = ref.read(wsClientProvider);
    final sub = client.messageStream.listen(_onMessage);
    ref.onDispose(sub.cancel);
    return [];
  }

  void _onMessage(WsMessage msg) {
    if (msg.type != 'detection') return;
    final event = DetectionEvent.fromJson(msg.data as Map<String, dynamic>);
    state = [...state, event];
  }

  /// Removes the resolved event from the front of the queue.
  void removeFirst() {
    if (state.isEmpty) return;
    state = state.sublist(1);
  }
}

final detectionQueueProvider =
    NotifierProvider<DetectionQueueNotifier, List<DetectionEvent>>(
        DetectionQueueNotifier.new);
