class DetectionEvent {
  final int droneId;
  final String cellId;
  final double rssDbm;
  final String? streamUrl;
  final double timestamp;
  final String detectionId;
  final String? callSessionId;

  const DetectionEvent({
    required this.droneId,
    required this.cellId,
    required this.rssDbm,
    required this.timestamp,
    required this.detectionId,
    this.streamUrl,
    this.callSessionId,
  });

  factory DetectionEvent.fromJson(Map<String, dynamic> json) => DetectionEvent(
    droneId: json['drone_id'] as int,
    cellId: json['cell_id'] as String,
    rssDbm: (json['rss_dbm'] as num).toDouble(),
    timestamp: (json['timestamp'] as num).toDouble(),
    detectionId: json['detection_id'] as String,
    streamUrl: json['stream_url'] as String?,
    callSessionId: json['call_session_id'] as String?,
  );
}
