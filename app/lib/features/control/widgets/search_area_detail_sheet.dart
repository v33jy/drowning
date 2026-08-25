import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/heatmap_cell.dart';
import '../providers/heatmap_provider.dart';
import '../providers/grid_provider.dart';
import 'search_area_guidance.dart';
import 'search_panel_components.dart';

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
    );
  }
}

class SearchAreaDetailSheet extends StatelessWidget {
  const SearchAreaDetailSheet({
    required this.cell,
    this.locationLabel = '위치 정보 없음',
    this.onClose,
    super.key,
  });

  final HeatmapCell cell;
  final String locationLabel;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final guidance = SearchAreaGuidance.fromCell(cell);

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
          if (cell.needsRecheck) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _review(cell.cellId, 'false_alarm'),
                    child: const Text('오탐 처리'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _review(cell.cellId, 'survivor_confirmed'),
                    child: const Text('요구조자 발견'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  Future<void> _review(String cellId, String outcome) async {
    await http.put(
      Uri.parse('${Config.baseUrl}/search/candidates/$cellId'),
      headers: {'Content-Type': 'application/json'},
      body: '{"outcome":"$outcome"}',
    );
  }
}

enum _DemoCallState { idle, connecting, connected, ended }

class _CallPreview extends StatefulWidget {
  const _CallPreview();

  @override
  State<_CallPreview> createState() => _CallPreviewState();
}

class _CallPreviewState extends State<_CallPreview> {
  _DemoCallState _callState = _DemoCallState.idle;

  Future<void> _connect() async {
    setState(() => _callState = _DemoCallState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted && _callState == _DemoCallState.connecting) {
      setState(() => _callState = _DemoCallState.connected);
    }
  }

  void _disconnect() => setState(() {
    _callState = _DemoCallState.ended;
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
  const _SectionSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.48),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.navy.withValues(alpha: 0.09)),
    ),
    child: child,
  );
}
