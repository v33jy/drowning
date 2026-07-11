import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../state/app_state.dart';

class WsService {
  final AppState _state;
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _disposed = false;

  WsService(this._state);

  Future<void> connect() async {
    if (_disposed) return;
    _state.setStatus(ConnectionStatus.connecting);
    try {
      _channel = WebSocketChannel.connect(Uri.parse(Config.wsUrl));
      // Await the WebSocket handshake before marking as connected.
      // Without this, status is set to "connected" before the TCP handshake
      // completes, hiding real connection failures.
      await _channel!.ready;
      if (_disposed) {
        await _channel!.sink.close();
        return;
      }
      _channel!.stream.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
      );
      _state.setStatus(ConnectionStatus.connected);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (msg['type'] as String) {
        case 'init':
          _state.applyInit(msg['data'] as Map<String, dynamic>);
        case 'drone_update':
          _state.updateDrone(msg['data'] as Map<String, dynamic>);
        case 'heatmap_update':
          _state.updateHeatmap(msg['data'] as List<dynamic>);
        case 'detection':
          _state.addDetection(msg['data'] as Map<String, dynamic>);
        case 'video_frame':
          _state.updateVideoFrame(msg['data'] as Map<String, dynamic>);
      }
    } catch (e) {
      // Malformed messages are discarded — don't disconnect over a bad packet.
      debugPrint('WsService: malformed message discarded: $e');
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _state.setStatus(ConnectionStatus.disconnected);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), connect);
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
  }
}
