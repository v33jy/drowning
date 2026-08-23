import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/heatmap_cell.dart';
import '../providers/heatmap_provider.dart';
import '../providers/grid_provider.dart';
import 'search_area_guidance.dart';
import 'search_panel_components.dart';
import 'video_review_section.dart';

class LiveSearchAreaDetail extends ConsumerWidget {
  const LiveSearchAreaDetail({
    required this.cellId,
    required this.onClose,
    super.key,
  });

  final String cellId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cell = ref.watch(
      heatmapProvider.select(
        (cells) => cells[cellId] ?? HeatmapCell.unscanned(cellId),
      ),
    );
    final locationLabel = locationLabelForCell(
      cellId: cellId,
      labels: ref.watch(gridLocationLabelProvider),
      grid: ref.watch(gridDefProvider),
    );
    return SearchAreaDetailSheet(
      cell: cell,
      locationLabel: locationLabel,
      onClose: onClose,
      videoReview: VideoReviewSection(cellId: cellId),
    );
  }
}

class SearchAreaDetailSheet extends StatelessWidget {
  const SearchAreaDetailSheet({
    required this.cell,
    this.locationLabel = '위치 정보 없음',
    this.onClose,
    this.videoReview,
    super.key,
  });

  final HeatmapCell cell;
  final String locationLabel;
  final VoidCallback? onClose;
  final Widget? videoReview;

  @override
  Widget build(BuildContext context) {
    final guidance = SearchAreaGuidance.fromCell(cell);
    final capturedAgo = formatSavedVideoAge(cell.lastUpdated);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SearchStatusHeader(
            status: guidance.statusLabel,
            statusColor: guidance.color,
            locationLabel: locationLabel,
            trailing: onClose == null
                ? Text(
                    formatLastChecked(cell.lastUpdated),
                    style: Theme.of(context).textTheme.labelSmall,
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatLastChecked(cell.lastUpdated),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: onClose,
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          SearchActionSummary(action: guidance.action, reason: guidance.reason),
          const SizedBox(height: AppSpacing.md),
          if (capturedAgo != null) ...[
            const _SectionLabel('저장된 영상'),
            const SizedBox(height: AppSpacing.sm),
            _SectionSurface(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _MockLiveVideo(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
                    child: Text(
                      '$capturedAgo 촬영',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  if (videoReview != null && !Config.demoMode)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: videoReview,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String? formatSavedVideoAge(DateTime? timestamp, {DateTime? now}) {
  if (timestamp == null) return null;
  final elapsed = (now ?? DateTime.now()).toUtc().difference(timestamp.toUtc());
  if (elapsed.isNegative || elapsed.inMinutes < 1) return '방금 전';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}분 전';
  if (elapsed.inHours < 24) return '${elapsed.inHours}시간 전';
  return null;
}

enum _DemoCallState { idle, connecting, connected, ended }

class _CallPreview extends StatefulWidget {
  const _CallPreview();

  @override
  State<_CallPreview> createState() => _CallPreviewState();
}

class _CallPreviewState extends State<_CallPreview> {
  _DemoCallState _callState = _DemoCallState.idle;
  bool _isSpeaking = false;
  bool _pushToTalkMode = false;
  bool _showPushToTalkHint = false;
  Timer? _hintTimer;

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  void _showPushToTalkHelp() {
    _hintTimer?.cancel();
    _showPushToTalkHint = true;
    _hintTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _showPushToTalkHint = false);
    });
  }

  Future<void> _connect() async {
    setState(() => _callState = _DemoCallState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted && _callState == _DemoCallState.connecting) {
      setState(() => _callState = _DemoCallState.connected);
    }
  }

  void _disconnect() => setState(() {
    _callState = _DemoCallState.ended;
    _isSpeaking = false;
    _pushToTalkMode = false;
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionLabel('요구조자 전화'),
      const SizedBox(height: AppSpacing.sm),
      _SectionSurface(child: _callContent),
    ],
  );

  Widget get _callContent => switch (_callState) {
    _DemoCallState.idle => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _CallStateLabel(label: '통화 대기', color: AppColors.textSecondary),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          key: const Key('connect-survivor-call'),
          onPressed: _connect,
          style: _primaryButtonStyle,
          child: const Text(
            '전화 연결',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
    _DemoCallState.connecting => const SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: AppSpacing.sm),
          Text(
            '연결 중…',
            style: TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
    _DemoCallState.connected => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF16845B),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            const Expanded(
              child: Text(
                '통화 중',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton.icon(
              onPressed: _disconnect,
              style: FilledButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFFC93434),
                minimumSize: const Size(104, 38),
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 9,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.call_end_rounded, size: 17),
              label: const Text(
                '통화 종료',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                key: const Key('voice-mode-selector'),
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('음성 전달'),
                    icon: Icon(Icons.mic_rounded, size: 17),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('눌러서 말하기'),
                    icon: Icon(Icons.touch_app_rounded, size: 17),
                  ),
                ],
                selected: {_pushToTalkMode},
                onSelectionChanged: (selection) => setState(() {
                  _pushToTalkMode = selection.first;
                  _isSpeaking = false;
                  if (_pushToTalkMode) _showPushToTalkHelp();
                }),
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  side: WidgetStatePropertyAll(
                    BorderSide(color: AppColors.navy.withValues(alpha: 0.18)),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 43,
              child: IgnorePointer(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      alignment: Alignment.bottomRight,
                      scale: Tween<double>(
                        begin: 0.94,
                        end: 1,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _showPushToTalkHint
                      ? const _PushToTalkHint(key: Key('push-to-talk-hint'))
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (!_pushToTalkMode)
          Container(
            key: const Key('continuous-voice-active'),
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF16845B).withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF16845B).withValues(alpha: 0.2),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.graphic_eq_rounded,
                  color: Color(0xFF13704E),
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  '음성 전달 중',
                  style: TextStyle(
                    color: Color(0xFF13704E),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          )
        else
          Semantics(
            button: true,
            label: '누르는 동안 말하기',
            child: GestureDetector(
              key: const Key('push-to-talk'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _isSpeaking = true),
              onTapUp: (_) => setState(() => _isSpeaking = false),
              onTapCancel: () => setState(() => _isSpeaking = false),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 140),
                scale: _isSpeaking ? 0.985 : 1,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _isSpeaking
                        ? const Color(0xFF0B6BCB)
                        : AppColors.navy,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (_isSpeaking
                                    ? const Color(0xFF0B6BCB)
                                    : AppColors.navy)
                                .withValues(alpha: _isSpeaking ? 0.3 : 0.22),
                        blurRadius: _isSpeaking ? 16 : 12,
                        offset: Offset(0, _isSpeaking ? 3 : 6),
                      ),
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.2),
                        blurRadius: 1,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isSpeaking
                            ? Icons.mic_rounded
                            : Icons.mic_none_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
                      const SizedBox(width: 9),
                      Text(
                        _isSpeaking ? '말하는 중' : '눌러서 말하기',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
    _DemoCallState.ended => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _CallStateLabel(label: '통화 종료됨', color: AppColors.textSecondary),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          key: const Key('reconnect-survivor-call'),
          onPressed: _connect,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.navy,
            minimumSize: const Size.fromHeight(44),
            side: BorderSide(color: AppColors.navy.withValues(alpha: 0.22)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            '다시 전화하기',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  };

  ButtonStyle get _primaryButtonStyle => FilledButton.styleFrom(
    backgroundColor: AppColors.navy,
    foregroundColor: Colors.white,
    minimumSize: const Size.fromHeight(44),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}

class _PushToTalkHint extends StatelessWidget {
  const _PushToTalkHint({super.key});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xF207203E),
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Text(
            '‘눌러서 말하기’ 버튼을 누르고 있는 동안만 구조대원의 음성이 전달됩니다.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Positioned(
          right: 28,
          bottom: 2,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: const SizedBox(
              width: 9,
              height: 9,
              child: ColoredBox(color: Color(0xF207203E)),
            ),
          ),
        ),
      ],
    ),
  );
}

class _CallStateLabel extends StatelessWidget {
  const _CallStateLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 7),
      Text(
        label,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: AppColors.navy,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.15,
    ),
  );
}

class _SectionSurface extends StatelessWidget {
  const _SectionSurface({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.48),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.navy.withValues(alpha: 0.09)),
    ),
    child: child,
  );
}

class _MockLiveVideo extends StatelessWidget {
  const _MockLiveVideo({this.canExpand = true});

  final bool canExpand;

  @override
  Widget build(BuildContext context) => Semantics(
    button: canExpand,
    label: canExpand ? '확인 영상 크게 보기' : '확대된 확인 영상',
    child: GestureDetector(
      key: canExpand ? const Key('expand-confirmation-video') : null,
      onTap: canExpand ? () => _showExpandedVideo(context) : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF19324D), Color(0xFF07182B)],
                  ),
                ),
              ),
              if (canExpand)
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
  );

  Future<void> _showExpandedVideo(BuildContext context) => showDialog<void>(
    context: context,
    barrierColor: const Color(0xE6000B18),
    builder: (dialogContext) => Dialog.fullscreen(
      backgroundColor: const Color(0xFF07182B),
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: const _MockLiveVideo(canExpand: false),
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
