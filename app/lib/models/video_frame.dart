import 'dart:convert';
import 'dart:typed_data';

class VideoFrameEvent {
  final int droneId;
  final int seq;
  final Uint8List bytes;

  const VideoFrameEvent({
    required this.droneId,
    required this.seq,
    required this.bytes,
  });

  factory VideoFrameEvent.fromJson(Map<String, dynamic> json) => VideoFrameEvent(
        droneId: json['drone_id'] as int,
        seq: json['seq'] as int,
        bytes: base64Decode(json['frame_b64'] as String),
      );
}
