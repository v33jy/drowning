import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ws_client.dart';
import 'ws_providers.dart';

/// Latest video frame per drone (base64 PNG) — just the last one, no
/// buffering. Rough live-glance thumbnail use only, not a real video player.
class VideoFrameNotifier extends Notifier<Map<int, String>> {
  @override
  Map<int, String> build() {
    final client = ref.read(wsClientProvider);
    final sub = client.messageStream.listen(_onMessage);
    ref.onDispose(sub.cancel);
    return {};
  }

  void _onMessage(WsMessage msg) {
    if (msg.type != 'video_frame') return;
    final data = msg.data as Map<String, dynamic>;
    final droneId = data['drone_id'] as int;
    final frameB64 = data['frame_b64'] as String;
    state = {...state, droneId: frameB64};
  }
}

final videoFrameProvider = NotifierProvider<VideoFrameNotifier, Map<int, String>>(VideoFrameNotifier.new);
