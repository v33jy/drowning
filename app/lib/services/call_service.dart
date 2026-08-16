import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import 'microphone_permission_guidance.dart';

export 'microphone_permission_guidance.dart' show CallRecoveryAction;

enum CallStatus { idle, connecting, active, reconnecting, disconnected }

Future<PermissionStatus> _currentMicrophonePermissionStatus() =>
    Permission.microphone.status;

@immutable
class CallState {
  const CallState(
    this.status, {
    this.sessionId,
    this.retryAttempt = 0,
    this.message,
    this.isTransmitting = false,
    this.recoveryAction = CallRecoveryAction.retry,
  });

  final CallStatus status;
  final String? sessionId;
  final int retryAttempt;
  final String? message;
  final bool isTransmitting;
  final CallRecoveryAction recoveryAction;

  bool get canRetry =>
      status == CallStatus.disconnected &&
      sessionId != null &&
      recoveryAction == CallRecoveryAction.retry;

  bool get requiresMicrophoneSettings =>
      status == CallStatus.disconnected &&
      recoveryAction == CallRecoveryAction.openMicrophoneSettings;
}

final callServiceProvider = StateNotifierProvider<CallService, CallState>(
  (ref) => CallService(),
);

class CallService extends StateNotifier<CallState> {
  CallService({
    this.maxReconnectAttempts = 3,
    this.reconnectDelay = const Duration(seconds: 2),
    this.connectionAttemptTimeout = const Duration(seconds: 10),
    Future<PermissionStatus> Function()? microphonePermissionStatus,
  }) : _microphonePermissionStatus =
           microphonePermissionStatus ?? _currentMicrophonePermissionStatus,
       super(const CallState(CallStatus.idle));

  final int maxReconnectAttempts;
  final Duration reconnectDelay;
  final Duration connectionAttemptTimeout;
  final Future<PermissionStatus> Function() _microphonePermissionStatus;

  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  WebSocketChannel? _signaling;
  StreamSubscription<dynamic>? _signalingSubscription;
  Timer? _reconnectTimer;
  Timer? _connectionAttemptTimer;
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;
  bool _disposed = false;
  bool _ending = false;
  int _connectionGeneration = 0;

  Future<void> startCall(String sessionId) async {
    if (_disposed ||
        state.status == CallStatus.connecting ||
        state.status == CallStatus.reconnecting ||
        state.status == CallStatus.active) {
      return;
    }
    _reconnectTimer?.cancel();
    state = CallState(CallStatus.connecting, sessionId: sessionId);
    await _connect(sessionId, isReconnect: false);
  }

  Future<void> retryCall() async {
    final sessionId = state.sessionId;
    if (_disposed || !state.canRetry || sessionId == null) return;
    _reconnectTimer?.cancel();
    state = CallState(CallStatus.connecting, sessionId: sessionId);
    await _connect(sessionId, isReconnect: false);
  }

  Future<void> _connect(String sessionId, {required bool isReconnect}) async {
    final generation = ++_connectionGeneration;
    if (Config.demoMode) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (_isCurrent(generation, sessionId)) {
        state = CallState(CallStatus.active, sessionId: sessionId);
      }
      return;
    }

    try {
      if (_localStream == null) {
        final permission = await Permission.microphone.request();
        if (!permission.isGranted) {
          final guidance = MicrophonePermissionGuidance.fromStatus(permission);
          state = CallState(
            CallStatus.disconnected,
            sessionId: sessionId,
            message: guidance.message,
            recoveryAction: guidance.recoveryAction,
          );
          return;
        }
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
        _setMicrophoneEnabled(false);
      }

      await _closeConnection(keepLocalStream: true);
      if (!_isCurrent(generation, sessionId)) return;
      _peer = await createPeerConnection({'iceServers': <dynamic>[]});
      for (final track in _localStream!.getAudioTracks()) {
        await _peer!.addTrack(track, _localStream!);
      }

      _signaling = WebSocketChannel.connect(
        Uri.parse(Config.callWsUrl(sessionId)),
      );
      await _signaling!.ready;
      if (!_isCurrent(generation, sessionId)) return;
      _signalingSubscription = _signaling!.stream.listen(
        _handleSignal,
        onError: (Object error) =>
            _handleTransientFailure(sessionId, generation, '음성 연결이 끊겼습니다.'),
        onDone: () =>
            _handleTransientFailure(sessionId, generation, '음성 연결이 끊겼습니다.'),
      );
      _connectionAttemptTimer = Timer(connectionAttemptTimeout, () {
        _handleTransientFailure(
          sessionId,
          generation,
          '상대방의 연결을 기다리는 시간이 초과됐습니다.',
        );
      });

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
        if (!_isCurrent(generation, sessionId)) return;
        if (connectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _connectionAttemptTimer?.cancel();
          state = CallState(CallStatus.active, sessionId: sessionId);
        } else if (connectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _handleTransientFailure(sessionId, generation, '음성 연결이 불안정합니다.');
        } else if (connectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _handleTransientFailure(sessionId, generation, '음성 연결이 끊겼습니다.');
        }
      };
    } catch (error) {
      debugPrint('통화를 ${isReconnect ? '다시 연결' : '시작'}하지 못했습니다: $error');
      await _handleTransientFailure(sessionId, generation, '음성 연결에 실패했습니다.');
    }
  }

  bool _isCurrent(int generation, String sessionId) =>
      !_disposed &&
      !_ending &&
      generation == _connectionGeneration &&
      state.sessionId == sessionId;

  Future<void> _handleTransientFailure(
    String sessionId,
    int generation,
    String message,
  ) async {
    if (!_isCurrent(generation, sessionId)) return;
    _setMicrophoneEnabled(false);
    final attempt = state.retryAttempt + 1;
    _connectionGeneration++;
    await _closeConnection(keepLocalStream: true);
    if (_disposed || _ending || state.sessionId != sessionId) return;

    if (attempt > maxReconnectAttempts) {
      await _closeConnection(keepLocalStream: false);
      state = CallState(
        CallStatus.disconnected,
        sessionId: sessionId,
        retryAttempt: maxReconnectAttempts,
        message: '$message 다시 시도해 주세요.',
      );
      return;
    }

    state = CallState(
      CallStatus.reconnecting,
      sessionId: sessionId,
      retryAttempt: attempt,
      message: message,
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay, () {
      if (!_disposed &&
          state.status == CallStatus.reconnecting &&
          state.sessionId == sessionId) {
        _connect(sessionId, isReconnect: true);
      }
    });
  }

  Future<void> _handleSignal(dynamic raw) async {
    final message = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (message['type']) {
      case 'peer-ready':
        await _sendOffer();
      case 'answer':
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

  Future<void> _sendOffer() async {
    final peer = _peer;
    if (peer == null) return;
    final offer = await peer.createOffer();
    await peer.setLocalDescription(offer);
    _send({'type': 'offer', 'sdp': offer.sdp, 'sdp_type': offer.type});
  }

  void _send(Map<String, dynamic> message) {
    _signaling?.sink.add(jsonEncode(message));
  }

  void startTransmitting() {
    if (_disposed || state.status != CallStatus.active) return;
    _setMicrophoneEnabled(true);
    state = CallState(
      state.status,
      sessionId: state.sessionId,
      retryAttempt: state.retryAttempt,
      message: state.message,
      isTransmitting: true,
    );
  }

  void stopTransmitting() {
    if (_disposed || !state.isTransmitting) return;
    _setMicrophoneEnabled(false);
    state = CallState(
      state.status,
      sessionId: state.sessionId,
      retryAttempt: state.retryAttempt,
      message: state.message,
    );
  }

  void _setMicrophoneEnabled(bool enabled) {
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  Future<bool> openMicrophoneSettings() => openAppSettings();

  Future<bool> refreshMicrophonePermission() async {
    if (_disposed || !state.requiresMicrophoneSettings) return false;
    final sessionId = state.sessionId;
    final permission = await _microphonePermissionStatus();
    if (!permission.isGranted ||
        _disposed ||
        !state.requiresMicrophoneSettings ||
        state.sessionId != sessionId) {
      return false;
    }

    state = CallState(
      CallStatus.disconnected,
      sessionId: sessionId,
      message: '마이크 권한이 확인되었습니다. 음성 통화를 다시 연결합니다.',
    );
    return true;
  }

  Future<void> _closeConnection({required bool keepLocalStream}) async {
    final subscription = _signalingSubscription;
    final signaling = _signaling;
    final peer = _peer;
    _signalingSubscription = null;
    _signaling = null;
    _peer = null;
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    _connectionAttemptTimer?.cancel();
    _connectionAttemptTimer = null;
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

  Future<void> endCall({bool notifyPeer = true}) async {
    if (_disposed || state.status == CallStatus.idle || _ending) return;
    _ending = true;
    _setMicrophoneEnabled(false);
    _reconnectTimer?.cancel();
    _connectionGeneration++;
    if (notifyPeer) _send({'type': 'call-end'});
    await _closeConnection(keepLocalStream: false);
    if (!_disposed) state = const CallState(CallStatus.idle);
    _ending = false;
  }

  @override
  void dispose() {
    if (state.status != CallStatus.idle) _send({'type': 'call-end'});
    _disposed = true;
    _ending = true;
    _connectionGeneration++;
    _reconnectTimer?.cancel();
    _closeConnection(keepLocalStream: false);
    super.dispose();
  }
}
