import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
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

  // Broadcast streams don't replay past events to late subscribers — and
  // BootScreen fully awaits connect() (which emits connecting → connected)
  // *before* ControlScreen (and its ConnectionBadge listener) even exist.
  // Without tracking the current value separately, every subscriber missed
  // both events and permanently fell back to the badge's default display
  // value, which is why it showed "재연결 중" forever on a perfectly healthy
  // connection.
  ConnectionStatus _status = ConnectionStatus.connecting;
  ConnectionStatus get status => _status;

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _messageController = StreamController<WsMessage>.broadcast();

  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<WsMessage> get messageStream => _messageController.stream;

  void _setStatus(ConnectionStatus s) {
    _status = s;
    _statusController.add(s);
  }

  Future<void> connect(String url) async {
    if (_disposed) return;
    _url = url;
    _reconnectTimer?.cancel();
    await _channel?.sink.close();

    _setStatus(ConnectionStatus.connecting);
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      // Await the handshake before declaring "connected" — otherwise a
      // dead server still briefly reports connected. Bounded by a timeout:
      // an unreachable host (e.g. a stale/wrong LAN IP on a real device)
      // can otherwise hang here indefinitely, leaving the badge stuck on
      // "재연결 중" forever instead of failing fast and retrying.
      await _channel!.ready.timeout(const Duration(seconds: 5));
      if (_disposed) {
        await _channel!.sink.close();
        return;
      }
      _channel!.stream.listen(
        _onRaw,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
      );
      _setStatus(ConnectionStatus.connected);
    } catch (e) {
      debugPrint('WsClient: connect to $url failed: $e');
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
    _setStatus(ConnectionStatus.disconnected);
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
