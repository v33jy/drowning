import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/heatmap_cell.dart';
import '../data/ws_client.dart';
import 'ws_providers.dart';

class HeatmapNotifier extends Notifier<Map<String, HeatmapCell>> {
  @override
  Map<String, HeatmapCell> build() {
    final client = ref.read(wsClientProvider);
    final sub = client.messageStream.listen(_onMessage);
    ref.onDispose(sub.cancel);
    return {};
  }

  void _onMessage(WsMessage msg) {
    switch (msg.type) {
      case 'init':
        final data = msg.data as Map<String, dynamic>;
        _apply(data['heatmap'] as List<dynamic>);
      case 'heatmap_update':
        _apply(msg.data as List<dynamic>);
    }
  }

  void _apply(List<dynamic> raw) {
    state = {
      for (final c in raw)
        (c['cell_id'] as String): HeatmapCell.fromJson(c as Map<String, dynamic>),
    };
  }
}

final heatmapProvider = NotifierProvider<HeatmapNotifier, Map<String, HeatmapCell>>(
    HeatmapNotifier.new);
