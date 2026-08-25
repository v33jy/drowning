import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/liquid_page_components.dart';
import '../../core/widgets/severity.dart';
import '../../core/widgets/status_chip.dart';
import '../../models/search_area_presentation.dart';
import '../control/providers/grid_provider.dart';
import '../control/providers/map_focus_provider.dart';
import '../control/operational_section.dart';
import '../control/widgets/operation_header.dart';
import '../detection/providers/detection_log_provider.dart';
import 'models/log_entry.dart';
import 'providers/combined_log_provider.dart';

enum _StatusFilter { pending, rescued, falseAlarm, alert }

String _statusFilterLabel(_StatusFilter f) => switch (f) {
  _StatusFilter.pending => SearchAreaCopy.candidateLabel,
  _StatusFilter.rescued => SearchAreaCopy.survivorFoundLabel,
  _StatusFilter.falseAlarm => SearchAreaCopy.falseAlarmLabel,
  _StatusFilter.alert => '경고',
};

/// 기록 — 수색 활동, 탐지 결과, 장비 경고를 시간순으로 보여주는 화면.
/// [combinedLogProvider]의 기록을 기간·상태·검색어로 필터링한다.
class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({
    required this.onNavigate,
    required this.onQueueTap,
    super.key,
  });

  final ValueChanged<OperationalSection> onNavigate;
  final VoidCallback onQueueTap;

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
    final now = DateTime.now();
    final todayCount = base
        .where(
          (e) =>
              e.timestamp.year == now.year &&
              e.timestamp.month == now.month &&
              e.timestamp.day == now.day,
        )
        .length;
    final recheckCount = base
        .where((e) => e.activityKind == LogActivityKind.areaNeedsRecheck)
        .length;
    final detectionCount = base
        .where((e) => e.type == LogEntryType.detection)
        .length;
    final alertCount = base
        .where(
          (e) =>
              e.type == LogEntryType.batteryLow ||
              e.type == LogEntryType.signalLost,
        )
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFE8EEF5),
      body: Stack(
        children: [
          const Positioned.fill(child: LiquidPageBackdrop()),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OperationHeader(
                  queueCount: ref.watch(
                    pendingDetectionQueueProvider.select((q) => q.length),
                  ),
                  onHomeTap: () =>
                      widget.onNavigate(OperationalSection.control),
                  onQueueTap: widget.onQueueTap,
                  onLogTap: () {},
                  onHelpTap: () => widget.onNavigate(OperationalSection.help),
                  onSettingsTap: () =>
                      widget.onNavigate(OperationalSection.settings),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1160),
                      child: SizedBox(
                        width: double.infinity,
                        child: _LogSummaryStrip(
                          todayCount: todayCount,
                          recheckCount: recheckCount,
                          detectionCount: detectionCount,
                          alertCount: alertCount,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1160),
                      child: LiquidGlassPanel(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final search = TextField(
                              controller: _searchController,
                              style: Theme.of(context).textTheme.bodyMedium,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search, size: 20),
                                hintText: '구역 · 활동 검색',
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
                            final filters = Wrap(
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
                                      : () => setState(() => _dateRange = null),
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
                            );
                            if (constraints.maxWidth >= 780) {
                              return Row(
                                children: [
                                  SizedBox(width: 300, child: search),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(child: filters),
                                ],
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                search,
                                const SizedBox(height: AppSpacing.sm),
                                filters,
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1160),
                        child: SizedBox(
                          width: double.infinity,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final desktop = constraints.maxWidth >= 880;
                              return Container(
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppColors.border.withValues(
                                      alpha: .8,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (desktop) const _LogTableHeader(),
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
                                                    color:
                                                        AppColors.textSecondary,
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
                                              padding: EdgeInsets.fromLTRB(
                                                desktop ? 0 : AppSpacing.lg,
                                                desktop ? 0 : AppSpacing.md,
                                                desktop ? 0 : AppSpacing.lg,
                                                desktop ? 0 : AppSpacing.lg,
                                              ),
                                              itemCount: filtered.length,
                                              separatorBuilder: (_, _) =>
                                                  desktop
                                                  ? const Divider(height: 1)
                                                  : const SizedBox(height: 8),
                                              itemBuilder: (context, i) =>
                                                  _LogTile(
                                                    entry: filtered[i],
                                                    desktop: desktop,
                                                  ),
                                            ),
                                    ),
                                  ],
                                ),
                              );
                            },
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

class _LogSummaryStrip extends StatelessWidget {
  const _LogSummaryStrip({
    required this.todayCount,
    required this.recheckCount,
    required this.detectionCount,
    required this.alertCount,
  });

  final int todayCount;
  final int recheckCount;
  final int detectionCount;
  final int alertCount;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final metrics = [
        _SummaryMetric(label: '오늘 기록', value: todayCount),
        _SummaryMetric(
          label: '재확인',
          value: recheckCount,
          color: AppColors.warning,
        ),
        _SummaryMetric(
          label: '탐지',
          value: detectionCount,
          color: AppColors.danger,
        ),
        _SummaryMetric(
          label: '장비 경고',
          value: alertCount,
          color: AppColors.warning,
        ),
      ];
      if (constraints.maxWidth >= 720) {
        return Row(
          children: [
            for (var i = 0; i < metrics.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: metrics[i]),
            ],
          ],
        );
      }
      final width = (constraints.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final metric in metrics) SizedBox(width: width, child: metric),
        ],
      );
    },
  );
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    this.color = AppColors.navy,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .64),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border.withValues(alpha: .78)),
      boxShadow: [
        BoxShadow(
          color: AppColors.navy.withValues(alpha: .035),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          '$value건',
          style: TextStyle(
            color: color,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

class _LogTableHeader extends StatelessWidget {
  const _LogTableHeader();

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.navy.withValues(alpha: .045),
    height: _LogTableLayout.headerHeight,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: _LogTableLayout.statusWidth, child: _ColumnLabel('상태')),
        _TableVerticalRule(),
        Expanded(
          flex: _LogTableLayout.locationFlex,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _LogTableLayout.cellPadding,
            ),
            child: _ColumnLabel('위치'),
          ),
        ),
        _TableVerticalRule(),
        Expanded(
          flex: _LogTableLayout.explanationFlex,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _LogTableLayout.cellPadding,
            ),
            child: _ColumnLabel('판단 내용'),
          ),
        ),
        _TableVerticalRule(),
        SizedBox(
          width: _LogTableLayout.timeWidth,
          child: Padding(
            padding: EdgeInsets.only(left: _LogTableLayout.cellPadding),
            child: _ColumnLabel('발생 시각'),
          ),
        ),
      ],
    ),
  );
}

abstract final class _LogTableLayout {
  static const headerHeight = 38.0;
  static const rowHeight = 46.0;
  static const statusWidth = 132.0;
  static const timeWidth = 190.0;
  static const cellPadding = 16.0;
  static const locationFlex = 3;
  static const explanationFlex = 4;
}

class _TableVerticalRule extends StatelessWidget {
  const _TableVerticalRule();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, color: AppColors.border.withValues(alpha: .8));
}

class _ColumnLabel extends StatelessWidget {
  const _ColumnLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      label,
      textAlign: TextAlign.left,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13.5,
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    ),
  );
}

class _LogTile extends ConsumerWidget {
  const _LogTile({required this.entry, required this.desktop});
  final LogEntry entry;
  final bool desktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = entry.severity.resolve(context);
    if (desktop) return _buildDesktop(context, ref, color);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: .78)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: .035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LogTitle(entry: entry, accentColor: color),
                const SizedBox(height: 2),
                Text(
                  _detailedTimeLabel(entry.timestamp),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (entry.type == LogEntryType.detection) ...[
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusChip(
                  severity: entry.severity,
                  label: _detectionStatusLabel(entry.status!),
                ),
                const SizedBox(height: 4),
                _mapButton(context, ref),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDesktop(BuildContext context, WidgetRef ref, Color color) {
    final location = _entryLocation(entry);
    return Container(
      height: _LogTableLayout.rowHeight,
      color: Colors.white.withValues(alpha: .72),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _LogTableLayout.statusWidth,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _entryStatusLabel(entry),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (entry.type == LogEntryType.detection) ...[
                      const SizedBox(width: 3),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      _mapButton(context, ref),
                    ],
                  ],
                ),
              ),
            ),
            const _TableVerticalRule(),
            Expanded(
              flex: _LogTableLayout.locationFlex,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _LogTableLayout.cellPadding,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const _TableVerticalRule(),
            Expanded(
              flex: _LogTableLayout.explanationFlex,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _LogTableLayout.cellPadding,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _entryExplanation(entry),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            const _TableVerticalRule(),
            SizedBox(
              width: _LogTableLayout.timeWidth,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: _LogTableLayout.cellPadding,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _detailedTimeLabel(entry.timestamp),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapButton(BuildContext context, WidgetRef ref) => IconButton(
    onPressed: () => _showOnMap(context, ref),
    tooltip: '지도에서 보기',
    icon: const Icon(Icons.map_outlined, size: 18),
    style: IconButton.styleFrom(
      foregroundColor: AppColors.navy,
      backgroundColor: AppColors.navy.withValues(alpha: .055),
      visualDensity: VisualDensity.compact,
      minimumSize: const Size(30, 30),
      maximumSize: const Size(30, 30),
      padding: EdgeInsets.zero,
    ),
  );

  void _showOnMap(BuildContext context, WidgetRef ref) {
    final event = entry.detectionEvent;
    if (event == null) return;

    final bounds = ref.read(gridDefProvider)[event.cellId];
    if (bounds != null) {
      ref.read(mapFocusRequestProvider.notifier).state = LatLng(
        (bounds.latMin + bounds.latMax) / 2,
        (bounds.lngMin + bounds.lngMax) / 2,
      );
    }
    ref.read(detectionFocusRequestProvider.notifier).state =
        DetectionFocusRequest(event: event, status: entry.status!);
    Navigator.of(context).pop();
  }
}

class _LogTitle extends StatelessWidget {
  const _LogTitle({required this.entry, required this.accentColor});

  final LogEntry entry;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final title = entry.title.replaceAll(' — ', ' - ');
    final separatorIndex = title.indexOf(' - ');
    final baseStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontSize: 16,
      height: 1.15,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    );

    if (separatorIndex < 0) {
      return Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(
            text: title.substring(0, separatorIndex),
            style: TextStyle(color: accentColor, fontWeight: FontWeight.w800),
          ),
          TextSpan(text: title.substring(separatorIndex)),
          if (entry.explanation case final explanation?)
            TextSpan(
              text: '  ·  $explanation',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

({String status, String content}) _titleParts(String rawTitle) {
  final title = rawTitle.replaceAll(' — ', ' - ');
  final separatorIndex = title.indexOf(' - ');
  if (separatorIndex < 0) return (status: '', content: title);
  return (
    status: title.substring(0, separatorIndex),
    content: title.substring(separatorIndex + 3),
  );
}

String _entryStatusLabel(LogEntry entry) {
  final parts = _titleParts(entry.title);
  if (parts.status.isNotEmpty) return parts.status;
  return switch (entry.type) {
    LogEntryType.detection => SearchAreaCopy.candidateLabel,
    LogEntryType.batteryLow => '장비 경고',
    LogEntryType.signalLost => '통신 경고',
    LogEntryType.activity => switch (entry.activityKind!) {
      LogActivityKind.searchStarted => '수색 시작',
      LogActivityKind.areaNeedsRecheck => SearchAreaCopy.candidateLabel,
      LogActivityKind.callConnecting => '통화 연결 중',
      LogActivityKind.callConnected => '통화 연결',
      LogActivityKind.callEnded => '통화 종료',
      LogActivityKind.detectionResolved => '탐지 처리',
    },
  };
}

String _entryLocation(LogEntry entry) {
  final hasLocation = switch (entry.type) {
    LogEntryType.detection => true,
    LogEntryType.activity =>
      entry.activityKind == LogActivityKind.areaNeedsRecheck ||
          entry.activityKind == LogActivityKind.detectionResolved,
    LogEntryType.batteryLow || LogEntryType.signalLost => false,
  };
  if (!hasLocation) return '';
  return _titleParts(entry.title).content;
}

String _entryExplanation(LogEntry entry) {
  if (entry.explanation case final explanation?) return explanation;
  return switch (entry.type) {
    LogEntryType.detection => switch (entry.status!) {
      DetectionStatus.pending => '강한 신호가 반복적으로 측정되어 현장 영상 확인이 필요합니다.',
      DetectionStatus.rescued => SearchAreaCopy.survivorFoundReason,
      DetectionStatus.falseAlarm => '현장 확인 결과 오탐으로 처리되었습니다.',
    },
    LogEntryType.batteryLow => '배터리 잔량이 경고 기준에 도달해 복귀 여부 확인이 필요합니다.',
    LogEntryType.signalLost => '기체 통신이 끊겨 마지막 위치와 연결 상태 확인이 필요합니다.',
    LogEntryType.activity => switch (entry.activityKind!) {
      LogActivityKind.searchStarted => '정상적으로 수색 임무를 시작했습니다.',
      LogActivityKind.areaNeedsRecheck => SearchAreaCopy.candidateLogReason,
      LogActivityKind.callConnecting => '요구조자와 음성 연결을 시도하고 있습니다.',
      LogActivityKind.callConnected => '요구조자와 음성 통화가 연결되었습니다.',
      LogActivityKind.callEnded => switch (entry.callDetails?.duration) {
        final Duration duration =>
          '음성 통화가 ${_durationLabel(duration)} 후 종료되었습니다.',
        null => '음성 연결 시도가 종료되었습니다.',
      },
      LogActivityKind.detectionResolved => '관제 담당자의 탐지 처리 결과가 기록되었습니다.',
    },
  };
}

String _durationLabel(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  if (minutes == 0) return '$seconds초';
  return '$minutes분 ${seconds.toString().padLeft(2, '0')}초';
}

String _clockLabel(DateTime timestamp) =>
    '${timestamp.month.toString().padLeft(2, '0')}/'
    '${timestamp.day.toString().padLeft(2, '0')} '
    '${timestamp.hour.toString().padLeft(2, '0')}:'
    '${timestamp.minute.toString().padLeft(2, '0')}:'
    '${timestamp.second.toString().padLeft(2, '0')}';

String _detectionStatusLabel(DetectionStatus status) => switch (status) {
  DetectionStatus.pending => SearchAreaCopy.candidateLabel,
  DetectionStatus.rescued => SearchAreaCopy.survivorFoundLabel,
  DetectionStatus.falseAlarm => SearchAreaCopy.falseAlarmLabel,
};

String _detailedTimeLabel(DateTime timestamp) =>
    '${_clockLabel(timestamp)}(${_relativeTimeLabel(timestamp)})';

String _relativeTimeLabel(DateTime timestamp) {
  final diff = DateTime.now().difference(timestamp);
  if (diff.isNegative || diff.inMinutes < 1) return '방금 전';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  return '${diff.inDays}일 전';
}
