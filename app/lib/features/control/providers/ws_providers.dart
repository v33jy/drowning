import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/connection_badge.dart';
import '../data/ws_client.dart';

/// Single [WsClient] instance for the app's lifetime. [BootScreen] calls
/// `.connect()` on it once the grid definition has been fetched; every
/// other provider only ever reads its streams.
final wsClientProvider = Provider<WsClient>((ref) {
  final client = WsClient();
  ref.onDispose(client.dispose);
  return client;
});

final wsConnectionProvider = StreamProvider<ConnectionStatus>((ref) async* {
  final client = ref.watch(wsClientProvider);
  // Seed with whatever the status already is — statusStream is a broadcast
  // stream, so a subscriber that starts watching after connect() already
  // ran (which is always, since BootScreen awaits it before ControlScreen
  // exists) would otherwise miss every past event and never see anything.
  yield client.status;
  yield* client.statusStream;
});
