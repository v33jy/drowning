import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/liquid_page_components.dart';
import '../../core/widgets/metric_row.dart';
import '../../core/widgets/severity.dart';
import '../../core/widgets/status_chip.dart';
import '../control/providers/grid_provider.dart';
import '../control/providers/map_focus_provider.dart';
import '../detection/providers/detection_log_provider.dart';
import 'models/log_entry.dart';
import 'providers/combined_log_provider.dart';

enum _StatusFilter { pending, rescued, falseAlarm, alert }

String _statusFilterLabel(_StatusFilter f) => switch (f) {
  _StatusFilter.pending => '대기',
  _StatusFilter.rescued => '구조 완료',
  _StatusFilter.falseAlarm => '오탐',
  _StatusFilter.alert => '경고',
};

/// 기록 — 수색 활동, 탐지 결과, 장비 경고를 시간순으로 보여주는 화면.
/// [combinedLogProvider]의 기록을 기간·상태·검색어로 필터링한다.
class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  String _query = '';
  DateTimeRange? _dateRange;
  final Set<_StatusFilter> _selectedStatuses = {};
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesStatus(LogEntry e) {
    if (_selectedStatuses.isEmpty) return true;
    return switch (e.type) {
      LogEntryType.detection => switch (e.status!) {
        DetectionStatus.pending => _selectedStatuses.contains(
          _StatusFilter.pending,
        ),
        DetectionStatus.rescued => _selectedStatuses.contains(
          _StatusFilter.rescued,
        ),
        DetectionStatus.falseAlarm => _selectedStatuses.contains(
          _StatusFilter.falseAlarm,
        ),
      },
      LogEntryType.batteryLow || LogEntryType.signalLost =>
        _selectedStatuses.contains(_StatusFilter.alert),
      LogEntryType.activity => false,
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
    final base = ref.watch(combinedLogProvider);

    final filtered = base.where((e) {
      if (_query.isNotEmpty &&
          !e.title.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      if (_dateRange != null) {
        final day = DateTime(
          e.timestamp.year,
          e.timestamp.month,
          e.timestamp.day,
        );
        final start = DateTime(
          _dateRange!.start.year,
          _dateRange!.start.month,
          _dateRange!.start.day,
        );
        final end = DateTime(
          _dateRange!.end.year,
          _dateRange!.end.month,
          _dateRange!.end.day,
        );
        if (day.isBefore(start) || day.isAfter(end)) return false;
      }
      if (!_matchesStatus(e)) return false;
      return true;
    }).toList();

    final urgentCount = base
        .where(
          (e) =>
              e.severity == Severity.danger || e.severity == Severity.warning,
        )
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFE8EEF5),
      body: Stack(
        children: [
          const Positioned.fill(
            child: LiquidPageBackdrop(startColor: Color(0xFFF4F8FC)),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LogHeader(
                  resultCount: filtered.length,
                  urgentCount: urgentCount,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1160),
                      child: LiquidGlassPanel(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final search = TextField(
                              controller: _searchController,
                              style: Theme.of(context).textTheme.bodyMedium,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search, size: 20),
                                hintText: '구역 · 드론 · 활동 검색',
                                suffixIcon: _query.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.close, size: 18),
                                        tooltip: '검색어 지우기',
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _query = '');
                                        },
                                      ),
                              ),
                              onChanged: (value) =>
                                  setState(() => _query = value),
                            );
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                search,
                                const SizedBox(height: AppSpacing.md),
                                Wrap(
                                  spacing: AppSpacing.sm,
                                  runSpacing: AppSpacing.sm,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _LogFilterChip(
                                      label: _dateRange == null
                                          ? '전체 기간'
                                          : '${_dateRange!.start.month}/${_dateRange!.start.day} ~ '
                                                '${_dateRange!.end.month}/${_dateRange!.end.day}',
                                      selected: _dateRange != null,
                                      onSelected: (_) => _pickDateRange(),
                                      avatarIcon: Icons.calendar_today_outlined,
                                      onDeleted: _dateRange == null
                                          ? null
                                          : () => setState(
                                              () => _dateRange = null,
                                            ),
                                    ),
                                    for (final status in _StatusFilter.values)
                                      _LogFilterChip(
                                        label: _statusFilterLabel(status),
                                        selected: _selectedStatuses.contains(
                                          status,
                                        ),
                                        onSelected: (selected) => setState(() {
                                          if (selected) {
                                            _selectedStatuses.add(status);
                                          } else {
                                            _selectedStatuses.remove(status);
                                          }
                                        }),
                                      ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1160),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: LiquidGlassPanel(
                          width: double.infinity,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.lg,
                                  AppSpacing.lg,
                                  AppSpacing.lg,
                                  AppSpacing.sm,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      '수색 활동',
                                      style: AppTypography.eyebrow(
                                        AppColors.navy,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '총 ${filtered.length}건',
                                      style: AppTypography.eyebrow(
                                        AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: filtered.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.inbox_outlined,
                                              size: 32,
                                              color: AppColors.textSecondary,
                                            ),
                                            const SizedBox(
                                              height: AppSpacing.sm,
                                            ),
                                            Text(
                                              '기록 없음',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodyMedium,
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.separated(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.lg,
                                        ),
                                        itemCount: filtered.length,
                                        separatorBuilder: (_, _) =>
                                            const Divider(height: 1),
                                        itemBuilder: (context, i) =>
                                            _LogTile(entry: filtered[i]),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogHeader extends StatelessWidget {
  const _LogHeader({required this.resultCount, required this.urgentCount});
  final int resultCount;
  final int urgentCount;
  @override
  Widget build(BuildContext context) => NavyPageHeader(
    title: '기록',
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeaderMetric(label: '조회 기록', value: '$resultCount건'),
        const SizedBox(width: 10),
        _HeaderMetric(
          label: '우선 확인',
          value: '$urgentCount건',
          alert: urgentCount > 0,
        ),
      ],
    ),
  );
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({
    required this.label,
    required this.value,
    this.alert = false,
  });
  final String label;
  final String value;
  final bool alert;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: .14)),
    ),
    child: Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .65),
            fontSize: 11,
          ),
        ),
        const SizedBox(width: 9),
        Text(
          value,
          style: TextStyle(
            color: alert ? const Color(0xFFFFC4A8) : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

/// Selected state is a solid navy fill + white label, not the default
/// Material checkmark — a plain FilterChip's checkmark stayed bright blue
/// regardless of [ChipThemeData], which read as an unrelated accent next to
/// the rest of this screen's navy-only "selected" language.
class _LogFilterChip extends StatelessWidget {
  const _LogFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.avatarIcon,
    this.onDeleted,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final IconData? avatarIcon;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.textPrimary;
    return FilterChip(
      label: Text(label),
      avatar: avatarIcon == null ? null : Icon(avatarIcon, size: 15, color: fg),
      selected: selected,
      onSelected: onSelected,
      onDeleted: onDeleted,
      showCheckmark: false,
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.navy,
      side: BorderSide(color: selected ? AppColors.navy : AppColors.border),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: fg,
      ),
      deleteIconColor: fg,
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});
  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = entry.severity.resolve(context);
    final icon = _entryIcon(entry);
    return InkWell(
      onTap: entry.type == LogEntryType.detection
          ? () => _showDetail(context)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon badge — what kind of event, and how urgent, at a glance.
            // A 3px color stripe alone was too easy to miss entirely.
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '드론 ${entry.droneId} · ${_entryTimeLabel(entry)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            if (entry.type == LogEntryType.detection) ...[
              const SizedBox(width: AppSpacing.sm),
              StatusChip(
                severity: entry.severity,
                label: _detectionStatusLabel(entry.status!),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Tooltip(
                message: '상세 확인',
                child: Icon(
                  Icons.chevron_right,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
            ],
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

String _entryTimeLabel(LogEntry entry) {
  final call = entry.callDetails;
  if (call == null) return _timeLabel(entry.timestamp);

  final started = _clockLabel(call.startedAt);
  final endedAt = call.endedAt;
  if (endedAt == null) return '시작 $started';
  return '시작 $started · 종료 ${_clockLabel(endedAt)} · ${_durationLabel(call.duration!)}';
}

String _clockLabel(DateTime timestamp) =>
    '${timestamp.month.toString().padLeft(2, '0')}/'
    '${timestamp.day.toString().padLeft(2, '0')} '
    '${timestamp.hour.toString().padLeft(2, '0')}:'
    '${timestamp.minute.toString().padLeft(2, '0')}:'
    '${timestamp.second.toString().padLeft(2, '0')}';

String _durationLabel(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  if (minutes == 0) return '$seconds초';
  return '$minutes분 ${seconds.toString().padLeft(2, '0')}초';
}

IconData _entryIcon(LogEntry entry) {
  return switch (entry.type) {
    LogEntryType.detection => switch (entry.status!) {
      DetectionStatus.pending => Icons.warning_amber_outlined,
      DetectionStatus.rescued => Icons.check_circle_outline,
      DetectionStatus.falseAlarm => Icons.cancel_outlined,
    },
    LogEntryType.batteryLow => Icons.battery_alert,
    LogEntryType.signalLost => Icons.wifi_off,
    LogEntryType.activity => switch (entry.activityKind!) {
      LogActivityKind.searchStarted => Icons.play_circle_outline,
      LogActivityKind.areaNeedsRecheck => Icons.radar,
      LogActivityKind.callConnecting => Icons.phone_forwarded_outlined,
      LogActivityKind.callConnected => Icons.phone_in_talk_outlined,
      LogActivityKind.callEnded => Icons.call_end_outlined,
      LogActivityKind.detectionResolved => Icons.task_alt,
    },
  };
}

String _detectionStatusLabel(DetectionStatus status) => switch (status) {
  DetectionStatus.pending => '처리 대기',
  DetectionStatus.rescued => '구조 완료',
  DetectionStatus.falseAlarm => '오탐',
};

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
                child: Text(
                  '드론 #${event.droneId} · ${locationLabelForCell(cellId: event.cellId, labels: ref.watch(gridLocationLabelProvider), grid: ref.watch(gridDefProvider))}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusChip(severity: entry.severity, label: statusLabel),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          MetricRow(
            label: 'RSS',
            value: event.rssDbm.toStringAsFixed(1),
            unit: 'dBm',
          ),
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
                // 관제가 더 이상 탭이 아니라 홈 화면이라, 시트를 닫고 기록
                // 화면 자체도 pop 해야 관제가 다시 보인다.
                Navigator.of(context)
                  ..pop()
                  ..pop();
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
