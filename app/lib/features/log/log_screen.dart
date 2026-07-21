import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/metric_row.dart';
import '../../core/widgets/severity.dart';
import '../../core/widgets/status_chip.dart';
import '../../navigation/tab_index_provider.dart';
import '../control/providers/grid_provider.dart';
import '../control/providers/map_focus_provider.dart';
import '../detection/providers/detection_log_provider.dart';
import 'models/log_entry.dart';
import 'providers/combined_log_provider.dart';

enum _LogFilter { all, unresolved }

/// 기록 — 구 "탐지 이력" + "알림 센터" 통합 화면. 데이터 소스는 하나
/// ([combinedLogProvider]/[unresolvedLogProvider]), 세그먼트로 필터만 바꾼다.
class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  _LogFilter _filter = _LogFilter.all;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final entries =
        ref.watch(_filter == _LogFilter.all ? combinedLogProvider : unresolvedLogProvider);
    final filtered = _query.isEmpty
        ? entries
        : entries.where((e) => e.title.toLowerCase().contains(_query.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('기록')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: '드론 · 셀 검색',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SegmentedButton<_LogFilter>(
              segments: const [
                ButtonSegment(value: _LogFilter.all, label: Text('전체')),
                ButtonSegment(value: _LogFilter.unresolved, label: Text('미확인')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('기록 없음', style: TextStyle(color: AppColors.textSecondary)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _LogTile(entry: filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});
  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: entry.type == LogEntryType.detection ? () => _showDetail(context) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SeverityStripe(severity: entry.severity),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(_timeLabel(entry.timestamp),
                      style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
            if (entry.type == LogEntryType.detection)
              const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    AppBottomSheet.show<void>(
      context: context,
      maxHeightFraction: 0.5,
      builder: (context) => _DetectionDetailSheet(entry: entry),
    );
  }
}

class _DetectionDetailSheet extends ConsumerWidget {
  const _DetectionDetailSheet({required this.entry});
  final LogEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = entry.detectionEvent!;
    final statusLabel = switch (entry.status!) {
      DetectionStatus.pending => '처리 대기',
      DetectionStatus.rescued => '구조 완료',
      DetectionStatus.falseAlarm => '오탐 처리됨',
    };

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('드론 #${event.droneId} · Cell ${event.cellId}',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              StatusChip(severity: entry.severity, label: statusLabel),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          MetricRow(label: 'RSS', value: event.rssDbm.toStringAsFixed(1), unit: 'dBm'),
          const SizedBox(height: AppSpacing.xs),
          MetricRow(label: '탐지 시각', value: _timeLabel(entry.timestamp)),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('지도에서 보기'),
              onPressed: () {
                final bounds = ref.read(gridDefProvider)[event.cellId];
                if (bounds != null) {
                  final center = LatLng(
                    (bounds.latMin + bounds.latMax) / 2,
                    (bounds.lngMin + bounds.lngMax) / 2,
                  );
                  ref.read(mapFocusRequestProvider.notifier).state = center;
                }
                ref.read(tabIndexProvider.notifier).state = 0;
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _timeLabel(DateTime t) {
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return '방금 전';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  return '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
