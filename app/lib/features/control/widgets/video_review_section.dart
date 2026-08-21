import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/video_bookmark.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/video_bookmark_provider.dart';

class VideoReviewSection extends ConsumerWidget {
  const VideoReviewSection({
    required this.cellId,
    this.demoMode = Config.demoMode,
    super.key,
  });

  final String cellId;
  final bool demoMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (demoMode) {
      return const SizedBox.shrink();
    }
    final bookmarks = ref.watch(videoBookmarksProvider(cellId));
    return bookmarks.when(
      data: (items) => items.isEmpty
          ? const Text('이 구역에 보존된 영상이 없습니다.')
          : VideoBookmarkHistory(
              bookmarks: items,
              baseUrl: ref.read(settingsProvider).baseUrl,
            ),
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const Text('영상 기록을 불러오지 못했습니다.'),
    );
  }
}

class VideoBookmarkHistory extends StatefulWidget {
  const VideoBookmarkHistory({
    required this.bookmarks,
    required this.baseUrl,
    super.key,
  });

  final List<VideoBookmark> bookmarks;
  final String baseUrl;

  @override
  State<VideoBookmarkHistory> createState() => _VideoBookmarkHistoryState();
}

class _VideoBookmarkHistoryState extends State<VideoBookmarkHistory> {
  String? _selectedBookmarkId;

  @override
  Widget build(BuildContext context) {
    final selected = widget.bookmarks.firstWhere(
      (item) => item.bookmarkId == _selectedBookmarkId,
      orElse: () => widget.bookmarks.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.bookmarks.length > 1) ...[
          DropdownButtonFormField<String>(
            initialValue: selected.bookmarkId,
            decoration: const InputDecoration(labelText: '영상 기록 선택'),
            items: [
              for (final bookmark in widget.bookmarks)
                DropdownMenuItem(
                  value: bookmark.bookmarkId,
                  child: Text(_formatBookmarkTime(bookmark.triggeredAt)),
                ),
            ],
            onChanged: (value) => setState(() => _selectedBookmarkId = value),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        VideoReviewCard(
          key: ValueKey(selected.bookmarkId),
          bookmark: selected,
          baseUrl: widget.baseUrl,
        ),
      ],
    );
  }
}

String _formatBookmarkTime(DateTime timestamp) {
  final local = timestamp.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${twoDigits(local.month)}/${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
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
        Semantics(
          button: true,
          label: '확인 영상 크게 보기',
          child: GestureDetector(
            key: const Key('expand-saved-video'),
            onTap: () => _showExpandedFrame(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildFrame(BoxFit.cover),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xCC06182C),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                        ),
                        child: const Icon(
                          Icons.open_in_full_rounded,
                          size: 17,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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

  Widget _buildFrame(BoxFit fit) => Image.network(
    widget.bookmark.frameUrl(widget.baseUrl, _frameIndex),
    fit: fit,
    errorBuilder: (_, _, _) => const Center(
      child: Text('장면을 표시할 수 없습니다.', style: TextStyle(color: Colors.white)),
    ),
  );

  Future<void> _showExpandedFrame(BuildContext context) => showDialog<void>(
    context: context,
    barrierColor: const Color(0xE6000B18),
    builder: (dialogContext) => Dialog.fullscreen(
      backgroundColor: const Color(0xFF07182B),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: _buildFrame(BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton.filledTonal(
                tooltip: '확대 영상 닫기',
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
