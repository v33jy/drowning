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

final wsConnectionProvider = StreamProvider<ConnectionStatus>((ref) {
  return ref.watch(wsClientProvider).statusStream;
});
