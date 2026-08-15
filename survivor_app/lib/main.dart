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

enum CallPhase { waiting, connecting, active, reconnecting, disconnected }

class SurvivorCallController extends ChangeNotifier {
  CallPhase phase = CallPhase.waiting;

  WebSocketChannel? _listener;
  WebSocketChannel? _signaling;
  StreamSubscription<dynamic>? _listenerSubscription;
  StreamSubscription<dynamic>? _signalingSubscription;
  Timer? _listenerReconnectTimer;
  Timer? _callReconnectTimer;
  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;
  bool _disposed = false;
  bool _ending = false;
  String? _sessionId;
  int _retryAttempt = 0;
  int _connectionGeneration = 0;
  static const maxReconnectAttempts = 3;

  int get retryAttempt => _retryAttempt;

  Future<void> start() async {
    if (_disposed) return;
    _listenerReconnectTimer?.cancel();
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
    _listenerReconnectTimer?.cancel();
    _listenerReconnectTimer = Timer(const Duration(seconds: 3), start);
  }

  Future<void> _handleIncoming(dynamic raw) async {
    final message = jsonDecode(raw as String) as Map<String, dynamic>;
    if (message['type'] != 'incoming_call' || phase != CallPhase.waiting) {
      return;
    }
    await _answerCall(message['session_id'] as String);
  }

  Future<void> _answerCall(String sessionId) async {
    _sessionId = sessionId;
    _retryAttempt = 0;
    phase = CallPhase.connecting;
    notifyListeners();

    await _connectCall(sessionId);
  }

  Future<void> _connectCall(String sessionId) async {
    final generation = ++_connectionGeneration;

    try {
      if (_localStream == null) {
        final permission = await Permission.microphone.request();
        if (!permission.isGranted) {
          phase = CallPhase.disconnected;
          notifyListeners();
          return;
        }
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
      }
      await _closeCallConnection(keepLocalStream: true);
      if (!_isCurrentCall(generation, sessionId)) return;
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
          _handleCallFailure(sessionId, generation);
        },
        onDone: () => _handleCallFailure(sessionId, generation),
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
        if (!_isCurrentCall(generation, sessionId)) return;
        if (connectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          phase = CallPhase.active;
          notifyListeners();
        } else if (connectionState ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            connectionState ==
                RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _handleCallFailure(sessionId, generation);
        }
      };
    } catch (error) {
      debugPrint('통화를 받을 준비를 하지 못했습니다: $error');
      await _handleCallFailure(sessionId, generation);
    }
  }

  bool _isCurrentCall(int generation, String sessionId) =>
      !_disposed &&
      !_ending &&
      generation == _connectionGeneration &&
      _sessionId == sessionId;

  Future<void> _handleCallFailure(String sessionId, int generation) async {
    if (!_isCurrentCall(generation, sessionId)) return;
    _connectionGeneration++;
    await _closeCallConnection(keepLocalStream: true);
    if (_disposed || _ending || _sessionId != sessionId) return;
    _retryAttempt++;
    if (_retryAttempt > maxReconnectAttempts) {
      _retryAttempt = maxReconnectAttempts;
      await _closeCallConnection(keepLocalStream: false);
      phase = CallPhase.disconnected;
      notifyListeners();
      return;
    }
    phase = CallPhase.reconnecting;
    notifyListeners();
    _callReconnectTimer?.cancel();
    _callReconnectTimer = Timer(const Duration(seconds: 2), () {
      if (!_disposed &&
          phase == CallPhase.reconnecting &&
          _sessionId == sessionId) {
        _connectCall(sessionId);
      }
    });
  }

  Future<void> retryCall() async {
    final sessionId = _sessionId;
    if (_disposed || phase != CallPhase.disconnected || sessionId == null) {
      return;
    }
    _retryAttempt = 0;
    phase = CallPhase.connecting;
    notifyListeners();
    await _connectCall(sessionId);
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
    _ending = true;
    _callReconnectTimer?.cancel();
    _connectionGeneration++;
    if (notifyPeer) _send({'type': 'call-end'});
    await _closeCallConnection(keepLocalStream: false);
    phase = CallPhase.waiting;
    _sessionId = null;
    _retryAttempt = 0;
    notifyListeners();
    _ending = false;
  }

  Future<void> _closeCallConnection({required bool keepLocalStream}) async {
    final subscription = _signalingSubscription;
    final signaling = _signaling;
    final peer = _peer;
    _signalingSubscription = null;
    _signaling = null;
    _peer = null;
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    await subscription?.cancel();
    await signaling?.sink.close();
    await peer?.close();
    if (!keepLocalStream) {
      for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
        track.stop();
      }
      await _localStream?.dispose();
      _localStream = null;
    }
  }

  @override
  void dispose() {
    if (phase != CallPhase.waiting) {
      _send({'type': 'call-end'});
    }
    _disposed = true;
    _ending = true;
    _connectionGeneration++;
    _listenerReconnectTimer?.cancel();
    _callReconnectTimer?.cancel();
    _listenerSubscription?.cancel();
    _listener?.sink.close();
    _closeCallConnection(keepLocalStream: false);
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
  const CallScreen({super.key, this.controller, this.autoStart = true});

  final SurvivorCallController? controller;
  final bool autoStart;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final SurvivorCallController controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    controller = widget.controller ?? SurvivorCallController();
    if (widget.autoStart) controller.start();
  }

  @override
  void dispose() {
    if (_ownsController) controller.dispose();
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
                      CallPhase.reconnecting => '통화 재연결 중',
                      CallPhase.disconnected => '통화 연결 끊김',
                    }, style: Theme.of(context).textTheme.headlineMedium),
                    if (controller.phase == CallPhase.reconnecting) ...[
                      const SizedBox(height: 12),
                      Text(
                        '자동 재연결 ${controller.retryAttempt}/'
                        '${SurvivorCallController.maxReconnectAttempts}',
                      ),
                    ],
                    if (inCall) ...[
                      const SizedBox(height: 48),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              controller.phase == CallPhase.disconnected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                        ),
                        onPressed: controller.phase == CallPhase.reconnecting
                            ? null
                            : controller.phase == CallPhase.disconnected
                            ? controller.retryCall
                            : controller.endCall,
                        icon: Icon(
                          controller.phase == CallPhase.disconnected
                              ? Icons.refresh
                              : Icons.call_end,
                        ),
                        label: Text(
                          controller.phase == CallPhase.disconnected
                              ? '다시 연결'
                              : '통화 종료',
                        ),
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
