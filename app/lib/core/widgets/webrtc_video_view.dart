import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import '../theme/app_colors.dart';

const _whepHeaders = {'Content-Type': 'application/sdp'};
const _iceGatheringTimeout = Duration(seconds: 3);

class WebRtcVideoView extends StatefulWidget {
  const WebRtcVideoView({required this.whepUrl, this.height = 240, super.key});

  final String? whepUrl;
  final double height;

  @override
  State<WebRtcVideoView> createState() => _WebRtcVideoViewState();
}

class _WebRtcVideoViewState extends State<WebRtcVideoView> {
  final _renderer = RTCVideoRenderer();
  RTCPeerConnection? _peer;
  Uri? _sessionUri;
  String? _error;
  bool _connected = false;
  bool _rendererInitialized = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(covariant WebRtcVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.whepUrl != widget.whepUrl) _connect();
  }

  Future<void> _connect() async {
    final url = widget.whepUrl;
    if (url == null || url.isEmpty) {
      if (mounted) setState(() => _error = '카메라 대기 중');
      return;
    }
    await _close();
    try {
      await _ensureRendererInitialized();
      final peer = await _createReceiver();
      await _exchangeOffer(peer, Uri.parse(url));
    } catch (_) {
      _setError('현장 영상을 연결하지 못했습니다.');
    }
  }

  Future<void> _ensureRendererInitialized() async {
    if (_rendererInitialized) return;
    await _renderer.initialize();
    _rendererInitialized = true;
  }

  Future<RTCPeerConnection> _createReceiver() async {
    final peer = await createPeerConnection({'iceServers': <dynamic>[]});
    _peer = peer;
    peer.onTrack = (event) {
      if (event.streams.isEmpty) return;
      _renderer.srcObject = event.streams.first;
      if (mounted) setState(() => _connected = true);
    };
    await peer.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    return peer;
  }

  Future<void> _exchangeOffer(RTCPeerConnection peer, Uri endpoint) async {
    final offer = await peer.createOffer();
    await peer.setLocalDescription(offer);
    await _waitForIceGathering(peer);
    final local = await peer.getLocalDescription();
    final response = await http.post(
      endpoint,
      headers: _whepHeaders,
      body: local?.sdp,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('WHEP HTTP ${response.statusCode}');
    }
    final location = response.headers['location'];
    if (location != null) _sessionUri = endpoint.resolve(location);
    await peer.setRemoteDescription(
      RTCSessionDescription(response.body, 'answer'),
    );
  }

  Future<void> _waitForIceGathering(RTCPeerConnection peer) async {
    if (await peer.getIceGatheringState() ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }
    final completer = Completer<void>();
    peer.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !completer.isCompleted) {
        completer.complete();
      }
    };
    await completer.future.timeout(_iceGatheringTimeout);
  }

  void _setError(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _close() async {
    final session = _sessionUri;
    _sessionUri = null;
    if (session != null) {
      unawaited(http.delete(session));
    }
    await _peer?.close();
    _peer = null;
    if (_rendererInitialized) _renderer.srcObject = null;
    _connected = false;
    _error = null;
  }

  @override
  void dispose() {
    _close();
    if (_rendererInitialized) _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    height: widget.height,
    width: double.infinity,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xFF07182B),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.navy.withValues(alpha: .18)),
    ),
    child: _connected
        ? RTCVideoView(
            _renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
        : Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error == null)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(
                    Icons.videocam_off_outlined,
                    color: Colors.white70,
                  ),
                const SizedBox(height: 9),
                Text(
                  _error ?? '현장 영상 연결 중',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
  );
}
