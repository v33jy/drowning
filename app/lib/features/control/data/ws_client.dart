import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/widgets/connection_badge.dart';

/// One decoded WS envelope: `{"type": ..., "data": ...}`.
class WsMessage {
  const WsMessage(this.type, this.data);
  final String type;
  final dynamic data;
}

/// Owns the WebSocket connection to the server. Deliberately knows nothing
/// about app state — it only exposes connection status and decoded messages
/// as broadcast streams, so each feature provider (drones/heatmap/detection)
/// subscribes and reacts only to the message types it cares about.
///
/// Takes the URL per [connect] call (rather than reading a static config)
/// so 설정 화면 can change the server address at runtime and force a
/// reconnect without recreating this client.
class WsClient {
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _disposed = false;
  String? _url;

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _messageController = StreamController<WsMessage>.broadcast();

  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<WsMessage> get messageStream => _messageController.stream;

  Future<void> connect(String url) async {
    if (_disposed) return;
    _url = url;
    _reconnectTimer?.cancel();
    await _channel?.sink.close();

    _statusController.add(ConnectionStatus.connecting);
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      // Await the handshake before declaring "connected" — otherwise a
      // dead server still briefly reports connected.
      await _channel!.ready;
      if (_disposed) {
        await _channel!.sink.close();
        return;
      }
      _channel!.stream.listen(
        _onRaw,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
      );
      _statusController.add(ConnectionStatus.connected);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onRaw(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      _messageController.add(WsMessage(msg['type'] as String, msg['data']));
    } catch (_) {
      // Malformed message discarded — don't tear down the connection over it.
    }
  }

  void _scheduleReconnect() {
    if (_disposed || _url == null) return;
    _statusController.add(ConnectionStatus.disconnected);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () => connect(_url!));
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _statusController.close();
    _messageController.close();
  }
}
