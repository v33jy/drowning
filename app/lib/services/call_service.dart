import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';

enum CallStatus { idle, connecting, active }

class CallState {
  const CallState(this.status, {this.sessionId});

  final CallStatus status;
  final String? sessionId;
}

final callServiceProvider = StateNotifierProvider<CallService, CallState>(
  (ref) => CallService(),
);

class CallService extends StateNotifier<CallState> {
  CallService() : super(const CallState(CallStatus.idle));

  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  WebSocketChannel? _signaling;
  StreamSubscription<dynamic>? _signalingSubscription;
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;
  bool _disposed = false;

  Future<void> startCall(String sessionId) async {
    if (_disposed || state.status != CallStatus.idle) return;
    state = CallState(CallStatus.connecting, sessionId: sessionId);

    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      debugPrint('마이크 권한이 없어 통화를 시작할 수 없습니다.');
      state = const CallState(CallStatus.idle);
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
        Uri.parse(Config.callWsUrl(sessionId)),
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
          state = CallState(CallStatus.active, sessionId: sessionId);
        } else if (connectionState ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            connectionState ==
                RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          endCall(notifyPeer: false);
        }
      };

      final offer = await _peer!.createOffer();
      await _peer!.setLocalDescription(offer);
      _send({'type': 'offer', 'sdp': offer.sdp, 'sdp_type': offer.type});
    } catch (error) {
      debugPrint('통화를 시작하지 못했습니다: $error');
      await endCall(notifyPeer: false);
    }
  }

  Future<void> _handleSignal(dynamic raw) async {
    final message = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (message['type']) {
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

  void _send(Map<String, dynamic> message) {
    _signaling?.sink.add(jsonEncode(message));
  }

  Future<void> endCall({bool notifyPeer = true}) async {
    if (_disposed || state.status == CallStatus.idle) return;
    if (notifyPeer) _send({'type': 'call-end'});
    state = const CallState(CallStatus.idle);
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
    if (state.status != CallStatus.idle) {
      _send({'type': 'call-end'});
    }
    _disposed = true;
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
