import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/drone_state.dart';
import '../data/ws_client.dart';
import 'ws_providers.dart';

class DronesNotifier extends Notifier<Map<int, DroneState>> {
  @override
  Map<int, DroneState> build() {
    final client = ref.read(wsClientProvider);
    final sub = client.messageStream.listen(_onMessage);
    ref.onDispose(sub.cancel);
    return {};
  }

  void _onMessage(WsMessage msg) {
    switch (msg.type) {
      case 'init':
        final data = msg.data as Map<String, dynamic>;
        final list = data['drones'] as List<dynamic>;
        state = {
          for (final d in list)
            (d['drone_id'] as int):
                DroneState.fromJson(d as Map<String, dynamic>),
        };
      case 'drone_update':
        final drone = DroneState.fromJson(msg.data as Map<String, dynamic>);
        state = {...state, drone.droneId: drone};
    }
  }
}

final dronesProvider =
    NotifierProvider<DronesNotifier, Map<int, DroneState>>(DronesNotifier.new);
