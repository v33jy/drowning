class VideoBookmark {
  const VideoBookmark({
    required this.bookmarkId,
    required this.cellId,
    required this.triggeredAt,
    required this.frameCount,
    required this.complete,
  });

  final String bookmarkId;
  final String cellId;
  final DateTime triggeredAt;
  final int frameCount;
  final bool complete;

  String frameUrl(String baseUrl, int frameIndex) =>
      '$baseUrl/drones/video/bookmarks/$bookmarkId/frames/$frameIndex';

  factory VideoBookmark.fromJson(Map<String, dynamic> json) => VideoBookmark(
    bookmarkId: json['bookmark_id'] as String,
    cellId: json['cell_id'] as String,
    triggeredAt: DateTime.fromMillisecondsSinceEpoch(
      ((json['triggered_at'] as num) * 1000).round(),
    ),
    frameCount: json['frame_count'] as int,
    complete: json['complete'] as bool? ?? true,
  );
}
