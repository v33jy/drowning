import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() => runApp(const SurvivorApp());

class ServerConfig {
  static const host = String.fromEnvironment(
    'SERVER_HOST',
    defaultValue: 'localhost',
  );
  static const port = int.fromEnvironment('HTTP_PORT', defaultValue: 8000);

  static String ws(String path) =>
      port == 443 ? 'wss://$host$path' : 'ws://$host:$port$path';
}

enum CallPhase { waiting, connecting, active }

class SurvivorCallController extends ChangeNotifier {
  CallPhase phase = CallPhase.waiting;

  WebSocketChannel? _listener;
  WebSocketChannel? _signaling;
  StreamSubscription<dynamic>? _listenerSubscription;
  StreamSubscription<dynamic>? _signalingSubscription;
  Timer? _reconnectTimer;
  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    try {
      _listener = WebSocketChannel.connect(
        Uri.parse(ServerConfig.ws('/survivors/listen')),
      );
      await _listener!.ready;
      _listenerSubscription = _listener!.stream.listen(
        _handleIncoming,
        onError: (Object error) {
          debugPrint('통화 대기 연결 오류: $error');
          _scheduleReconnect();
        },
        onDone: _scheduleReconnect,
      );
    } catch (error) {
      debugPrint('통화 대기 서버에 연결하지 못했습니다: $error');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _listenerSubscription?.cancel();
    _listenerSubscription = null;
    _listener = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), start);
  }

  Future<void> _handleIncoming(dynamic raw) async {
    final message = jsonDecode(raw as String) as Map<String, dynamic>;
    if (message['type'] != 'incoming_call' || phase != CallPhase.waiting) {
      return;
    }
    await _answerCall(message['session_id'] as String);
  }

  Future<void> _answerCall(String sessionId) async {
    phase = CallPhase.connecting;
    notifyListeners();

    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      debugPrint('마이크 권한이 없어 통화를 받을 수 없습니다.');
      phase = CallPhase.waiting;
      notifyListeners();
      return;
    }

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      _peer = await createPeerConnection({'iceServers': <dynamic>[]});
      for (final track in _localStream!.getAudioTracks()) {
        await _peer!.addTrack(track, _localStream!);
      }

      _signaling = WebSocketChannel.connect(
        Uri.parse(ServerConfig.ws('/calls/$sessionId/survivor')),
      );
      await _signaling!.ready;
      _signalingSubscription = _signaling!.stream.listen(
        _handleSignal,
        onError: (Object error) {
          debugPrint('통화 signaling 연결 오류: $error');
          endCall(notifyPeer: false);
        },
        onDone: () => endCall(notifyPeer: false),
      );

      _peer!.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        _send({
          'type': 'ice-candidate',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      };
      _peer!.onConnectionState = (connectionState) {
        if (_disposed) return;
        if (connectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          phase = CallPhase.active;
          notifyListeners();
        } else if (connectionState ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            connectionState ==
                RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          endCall(notifyPeer: false);
        }
      };
    } catch (error) {
      debugPrint('통화를 받을 준비를 하지 못했습니다: $error');
      await endCall(notifyPeer: false);
    }
  }

  Future<void> _handleSignal(dynamic raw) async {
    final message = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (message['type']) {
      case 'offer':
        await _peer?.setRemoteDescription(
          RTCSessionDescription(
            message['sdp'] as String?,
            message['sdp_type'] as String?,
          ),
        );
        _remoteDescriptionSet = true;
        for (final candidate in _pendingCandidates) {
          await _peer?.addCandidate(candidate);
        }
        _pendingCandidates.clear();
        final answer = await _peer!.createAnswer();
        await _peer!.setLocalDescription(answer);
        _send({'type': 'answer', 'sdp': answer.sdp, 'sdp_type': answer.type});
      case 'ice-candidate':
        final candidate = RTCIceCandidate(
          message['candidate'] as String?,
          message['sdpMid'] as String?,
          message['sdpMLineIndex'] as int?,
        );
        if (_remoteDescriptionSet) {
          await _peer?.addCandidate(candidate);
        } else {
          _pendingCandidates.add(candidate);
        }
      case 'call-end':
        await endCall(notifyPeer: false);
    }
  }

  void _send(Map<String, dynamic> message) {
    _signaling?.sink.add(jsonEncode(message));
  }

  Future<void> endCall({bool notifyPeer = true}) async {
    if (phase == CallPhase.waiting) return;
    if (notifyPeer) _send({'type': 'call-end'});
    phase = CallPhase.waiting;
    notifyListeners();
    await _signalingSubscription?.cancel();
    _signalingSubscription = null;
    await _signaling?.sink.close();
    _signaling = null;
    await _peer?.close();
    _peer = null;
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
  }

  @override
  void dispose() {
    if (phase != CallPhase.waiting) {
      _send({'type': 'call-end'});
    }
    _disposed = true;
    _reconnectTimer?.cancel();
    _listenerSubscription?.cancel();
    _listener?.sink.close();
    _signalingSubscription?.cancel();
    _signaling?.sink.close();
    _peer?.close();
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    _localStream?.dispose();
    super.dispose();
  }
}

class SurvivorApp extends StatelessWidget {
  const SurvivorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '요구조자 통화',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0B50D0),
        useMaterial3: true,
      ),
      home: const CallScreen(),
    );
  }
}

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final SurvivorCallController controller;

  @override
  void initState() {
    super.initState();
    controller = SurvivorCallController()..start();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final inCall = controller.phase != CallPhase.waiting;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(inCall ? Icons.call : Icons.wifi_calling_3, size: 88),
                    const SizedBox(height: 24),
                    Text(switch (controller.phase) {
                      CallPhase.waiting => '통화 대기 중',
                      CallPhase.connecting => '통화 연결 중',
                      CallPhase.active => '통화 중',
                    }, style: Theme.of(context).textTheme.headlineMedium),
                    if (inCall) ...[
                      const SizedBox(height: 48),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: controller.endCall,
                        icon: const Icon(Icons.call_end),
                        label: const Text('통화 종료'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
