import 'dart:async' show StreamSubscription, unawaited;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_sound/flutter_sound.dart';
import 'package:record/record.dart';

import '../config.dart';

// Binary packet header: [uuid:16][role:1][seq:4] = 21 bytes
// role = 1 → CONTROL APP (matches server's Role.CONTROL)
const int _headerSize = 21;
const int _roleControl = 1;

// 16 kHz mono 16-bit PCM: 20 ms frame = 640 bytes → bufferSize = 640 samples
const int _sampleRate = 16000;
const int _bufferSize = 640;

class VoipService {
  final AudioRecorder _recorder = AudioRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  RawDatagramSocket? _socket;
  InternetAddress? _serverAddress;
  StreamSubscription<Uint8List>? _recordSub;
  String? _sessionId;
  int _seq = 0;
  bool _active = false;
  bool _muted = false;
  bool _playerReady = false;

  bool get isActive => _active;
  bool get isMuted => _muted;

  /// Pauses/resumes the mic → server uplink without tearing down the
  /// recorder or losing the relay registration. A UI mute toggle that
  /// didn't actually stop outgoing audio would be misleading in a rescue
  /// call, so this has to be real, not just a visual state.
  void setMuted(bool muted) {
    _muted = muted;
    if (muted) {
      _recordSub?.pause();
    } else {
      _recordSub?.resume();
    }
  }

  Future<void> startCall(String sessionId) async {
    if (_active) return;
    _sessionId = sessionId;
    _seq = 0;
    _muted = false;

    // Resolve hostname → IP (InternetAddress() rejects "localhost" on iOS).
    // Raw UDP sockets are a dart:io platform API — there is no browser API
    // for arbitrary UDP, so this always throws UnsupportedError on Flutter
    // Web. That's a real platform limitation (VoIP only ever targeted
    // Android/iOS), not something to retry — it must propagate so CallSheet
    // can show a real "not supported here" message instead of hanging.
    final resolved = await InternetAddress.lookup(Config.serverHost);
    _serverAddress = resolved.first;

    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

    // Player must be fully ready *before* the socket listener is attached —
    // otherwise a datagram arriving mid-setup triggers feedUint8FromStream()
    // on a player that hasn't finished starting yet, which crashes native
    // audio playback (SIGSEGV in AudioTrack.write on Android) instead of
    // throwing a catchable Dart exception.
    bool playerReady = false;
    try {
      await _player.openPlayer();
      await _player.startPlayerFromStream(
        codec: Codec.pcm16,
        interleaved: true,
        numChannels: 1,
        sampleRate: _sampleRate,
        bufferSize: _bufferSize,
      );
      playerReady = true;
    } catch (e) {
      debugPrint('VoipService: player init failed: $e');
    }
    _playerReady = playerReady;

    _socket!.listen(_onDatagram);

    // Register with relay immediately — sends a silent CONTROL frame so the
    // relay knows our address before any mic audio arrives.
    _sendAudio(Uint8List(_bufferSize));

    // Mic capture: best-effort — receive-only mode works even if recorder fails.
    try {
      final recordStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );
      _recordSub = recordStream.listen(_sendAudio);
    } catch (e) {
      debugPrint('VoipService: recorder failed (simulator?): $e');
    }

    _active = true;
  }

  Future<void> stopCall() async {
    if (!_active) return;
    _active = false;
    _playerReady = false;

    await _recordSub?.cancel();
    await _recorder.stop();
    await _player.stopPlayer();
    await _player.closePlayer();
    _socket?.close();
    _socket = null;
    _serverAddress = null;
    _sessionId = null;
  }

  // dispose() must be synchronous (Flutter requirement), so async cleanup is
  // launched as a detached future. _recorder.dispose() is awaited inside so
  // it only runs after stopCall() fully completes — no race condition.
  void dispose() {
    unawaited(_disposeAsync());
  }

  Future<void> _disposeAsync() async {
    await stopCall();
    _recorder.dispose();
  }

  // -- Private --

  void _sendAudio(Uint8List pcm) {
    if (_socket == null || _sessionId == null || _serverAddress == null) return;
    _socket!.send(_buildPacket(pcm), _serverAddress!, Config.voipPort);
    _seq++;
  }

  void _onDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null || datagram.data.length <= _headerSize) return;
    if (!_playerReady) return; // player torn down or never finished starting
    final pcm = datagram.data.sublist(_headerSize);
    // feedUint8FromStream is async; fire-and-forget is intentional here —
    // blocking the UDP receive loop would cause packet loss.
    unawaited(_player.feedUint8FromStream(pcm));
  }

  Uint8List _buildPacket(Uint8List audio) {
    final hex = _sessionId!.replaceAll('-', '');
    final uuidBytes = Uint8List.fromList(
      List.generate(16, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)),
    );
    final header = ByteData(_headerSize);
    for (var i = 0; i < 16; i++) {
      header.setUint8(i, uuidBytes[i]);
    }
    header.setUint8(16, _roleControl);
    header.setUint32(17, _seq, Endian.big);
    return Uint8List.fromList([...header.buffer.asUint8List(), ...audio]);
  }
}
