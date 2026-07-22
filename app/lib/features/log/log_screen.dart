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

enum _StatusFilter { pending, rescued, falseAlarm, alert }

String _statusFilterLabel(_StatusFilter f) => switch (f) {
      _StatusFilter.pending => '대기',
      _StatusFilter.rescued => '구조 완료',
      _StatusFilter.falseAlarm => '오탐',
      _StatusFilter.alert => '경고',
    };

/// 기록 — 구 "탐지 이력" + "알림 센터" 통합 화면. 데이터 소스는 하나
/// ([combinedLogProvider]/[unresolvedLogProvider]), 세그먼트/필터는 그 위에서
/// 걸러낼 뿐 별도 상태를 두지 않는다.
class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  _LogFilter _filter = _LogFilter.all;
  String _query = '';
  DateTimeRange? _dateRange;
  final Set<int> _selectedDrones = {};
  final Set<_StatusFilter> _selectedStatuses = {};

  bool _matchesStatus(LogEntry e) {
    if (_selectedStatuses.isEmpty) return true;
    return switch (e.type) {
      LogEntryType.detection => switch (e.status!) {
          DetectionStatus.pending => _selectedStatuses.contains(_StatusFilter.pending),
          DetectionStatus.rescued => _selectedStatuses.contains(_StatusFilter.rescued),
          DetectionStatus.falseAlarm => _selectedStatuses.contains(_StatusFilter.falseAlarm),
        },
      LogEntryType.batteryLow ||
      LogEntryType.signalLost =>
        _selectedStatuses.contains(_StatusFilter.alert),
    };
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: _dateRange,
    );
    if (range != null) setState(() => _dateRange = range);
  }

  @override
  Widget build(BuildContext context) {
    final base =
        ref.watch(_filter == _LogFilter.all ? combinedLogProvider : unresolvedLogProvider);

    final availableDrones = base.map((e) => e.droneId).toSet().toList()..sort();

    final filtered = base.where((e) {
      if (_query.isNotEmpty && !e.title.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      if (_dateRange != null) {
        final day = DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day);
        final start = DateTime(_dateRange!.start.year, _dateRange!.start.month, _dateRange!.start.day);
        final end = DateTime(_dateRange!.end.year, _dateRange!.end.month, _dateRange!.end.day);
        if (day.isBefore(start) || day.isAfter(end)) return false;
      }
      if (_selectedDrones.isNotEmpty && !_selectedDrones.contains(e.droneId)) return false;
      if (!_matchesStatus(e)) return false;
      return true;
    }).toList();

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
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: SegmentedButton<_LogFilter>(
              segments: const [
                ButtonSegment(value: _LogFilter.all, label: Text('전체')),
                ButtonSegment(value: _LogFilter.unresolved, label: Text('미확인')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: Text(_dateRange == null
                        ? '날짜: 전체'
                        : '${_dateRange!.start.month}/${_dateRange!.start.day} ~ '
                            '${_dateRange!.end.month}/${_dateRange!.end.day}'),
                    selected: _dateRange != null,
                    onSelected: (_) => _pickDateRange(),
                    avatar: const Icon(Icons.calendar_today_outlined, size: 16),
                    onDeleted: _dateRange == null ? null : () => setState(() => _dateRange = null),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  for (final d in availableDrones) ...[
                    FilterChip(
                      label: Text('드론 #$d'),
                      selected: _selectedDrones.contains(d),
                      onSelected: (sel) => setState(
                        () => sel ? _selectedDrones.add(d) : _selectedDrones.remove(d),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  for (final s in _StatusFilter.values) ...[
                    FilterChip(
                      label: Text(_statusFilterLabel(s)),
                      selected: _selectedStatuses.contains(s),
                      onSelected: (sel) => setState(
                        () => sel ? _selectedStatuses.add(s) : _selectedStatuses.remove(s),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
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
