import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../models/video_bookmark.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/video_bookmark_provider.dart';

class VideoReviewSection extends ConsumerWidget {
  const VideoReviewSection({required this.cellId, super.key});

  final String cellId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(videoBookmarksProvider(cellId));
    return bookmarks.when(
      data: (items) => items.isEmpty
          ? const Text('이 구역에 보존된 영상이 없습니다.')
          : VideoReviewCard(
              bookmark: items.first,
              baseUrl: ref.read(settingsProvider).baseUrl,
            ),
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const Text('영상 기록을 불러오지 못했습니다.'),
    );
  }
}

class VideoReviewCard extends StatefulWidget {
  const VideoReviewCard({
    required this.bookmark,
    required this.baseUrl,
    super.key,
  });

  final VideoBookmark bookmark;
  final String baseUrl;

  @override
  State<VideoReviewCard> createState() => _VideoReviewCardState();
}

class _VideoReviewCardState extends State<VideoReviewCard> {
  var _frameIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.bookmark.frameCount == 0) {
      return const Text('신호 발생 시점에 수신된 카메라 장면이 없습니다.');
    }
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.network(
              widget.bookmark.frameUrl(widget.baseUrl, _frameIndex),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Center(child: Text('장면을 표시할 수 없습니다.')),
            ),
          ),
        ),
        if (widget.bookmark.frameCount > 1) _buildFrameNavigation(),
      ],
    );
  }

  Widget _buildFrameNavigation() => Row(
    children: [
      IconButton(
        tooltip: '이전 장면',
        onPressed: _frameIndex == 0 ? null : () => _moveFrame(-1),
        icon: const Icon(Icons.chevron_left),
      ),
      Expanded(
        child: Text(
          '${_frameIndex + 1} / ${widget.bookmark.frameCount}',
          textAlign: TextAlign.center,
        ),
      ),
      IconButton(
        tooltip: '다음 장면',
        onPressed: _frameIndex == widget.bookmark.frameCount - 1
            ? null
            : () => _moveFrame(1),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );

  void _moveFrame(int offset) {
    setState(() => _frameIndex += offset);
  }
}
