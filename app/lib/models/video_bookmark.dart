class VideoBookmark {
  const VideoBookmark({
    required this.bookmarkId,
    required this.cellId,
    required this.triggeredAt,
    required this.frameCount,
  });

  final String bookmarkId;
  final String cellId;
  final DateTime triggeredAt;
  final int frameCount;

  factory VideoBookmark.fromJson(Map<String, dynamic> json) => VideoBookmark(
    bookmarkId: json['bookmark_id'] as String,
    cellId: json['cell_id'] as String,
    triggeredAt: DateTime.fromMillisecondsSinceEpoch(
      ((json['triggered_at'] as num) * 1000).round(),
    ),
    frameCount: json['frame_count'] as int,
  );
}
