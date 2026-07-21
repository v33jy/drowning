import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/metric_row.dart';
import '../../../core/widgets/severity.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../models/drone_state.dart';
import '../providers/drones_provider.dart';
import '../providers/heatmap_provider.dart';
import 'marker_layer.dart';

const double _kPeek = 0.15;
const double _kMid = 0.5;
const double _kFull = 0.9;
const double _kTableThreshold = 0.75;

/// Drone list Bottom Sheet — persistent, always peeking. Dragging past
/// [_kTableThreshold] switches the same data into a table layout, which is
/// what used to be a separate "드론 관리" screen — there is no dedicated
/// route for it anymore, this sheet's expanded state *is* that screen.
class DroneListSheet extends ConsumerStatefulWidget {
  const DroneListSheet({super.key});

  @override
  ConsumerState<DroneListSheet> createState() => _DroneListSheetState();
}

class _DroneListSheetState extends ConsumerState<DroneListSheet> {
  double _extent = _kPeek;

  @override
  Widget build(BuildContext context) {
    final drones = ref.watch(dronesProvider);
    final heatmap = ref.watch(heatmapProvider);
    final rows = [
      for (final d in drones.values.toList()
        ..sort((a, b) => _severityRank(a).compareTo(_severityRank(b))))
        _DroneRow(drone: d, rssDbm: heatmap[d.cellId]?.rssDbm),
    ];
    final showTable = _extent >= _kTableThreshold;

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        setState(() => _extent = notification.extent);
        return false;
      },
      child: DraggableScrollableSheet(
        initialChildSize: _kPeek,
        minChildSize: _kPeek,
        maxChildSize: _kFull,
        snap: true,
        snapSizes: const [_kPeek, _kMid, _kFull],
        builder: (context, scrollController) {
          return DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
              boxShadow: [
                BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, -2)),
              ],
            ),
            child: Column(
              children: [
                const SheetHandle(),
                Expanded(
                  child: rows.isEmpty
                      ? const _EmptyDrones()
                      : showTable
                          ? _DroneTable(rows: rows, scrollController: scrollController)
                          : _DroneCardList(rows: rows, scrollController: scrollController),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

int _severityRank(DroneState d) {
  return switch (droneSeverity(d)) {
    Severity.danger => 0,
    Severity.offline => 1,
    Severity.warning => 2,
    Severity.ok => 3,
  };
}

class _DroneRow {
  const _DroneRow({required this.drone, required this.rssDbm});
  final DroneState drone;
  final double? rssDbm;
}

class _EmptyDrones extends StatelessWidget {
  const _EmptyDrones();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('연결된 드론 없음', style: TextStyle(color: AppColors.textSecondary)),
    );
  }
}

/// Peek/mid state — one card per drone with the 7 fields the design calls
/// for (ID/Battery/Altitude/Position/RSS/Cell/Status).
class _DroneCardList extends StatelessWidget {
  const _DroneCardList({required this.rows, required this.scrollController});
  final List<_DroneRow> rows;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) => _DroneCard(row: rows[i]),
    );
  }
}

class _DroneCard extends StatelessWidget {
  const _DroneCard({required this.row});
  final _DroneRow row;

  @override
  Widget build(BuildContext context) {
    final d = row.drone;
    final severity = droneSeverity(d);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('드론 #${d.droneId}', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              StatusChip(severity: severity, label: _statusLabel(d.status)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          MetricRow(label: '배터리', value: '${d.battery}', unit: '%'),
          const SizedBox(height: AppSpacing.xs),
          MetricRow(label: '고도', value: d.altitude.toStringAsFixed(0), unit: 'm'),
          const SizedBox(height: AppSpacing.xs),
          MetricRow(
            label: '위치',
            value: '${d.lat.toStringAsFixed(4)}, ${d.lng.toStringAsFixed(4)}',
          ),
          const SizedBox(height: AppSpacing.xs),
          MetricRow(
            label: 'RSS',
            value: row.rssDbm?.toStringAsFixed(1) ?? '—',
            unit: row.rssDbm != null ? 'dBm' : null,
          ),
          const SizedBox(height: AppSpacing.xs),
          MetricRow(label: '셀', value: d.cellId ?? '—'),
        ],
      ),
    );
  }
}

/// Full state (>=90%) — replaces the old dedicated "드론 관리" table screen.
/// Horizontal scroll rather than collapsing columns, per the engineering
/// review (comparing many drones at once matters more than fitting one
/// screen width).
class _DroneTable extends StatelessWidget {
  const _DroneTable({required this.rows, required this.scrollController});
  final List<_DroneRow> rows;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('DRONE')),
            DataColumn(label: Text('BATTERY'), numeric: true),
            DataColumn(label: Text('ALT'), numeric: true),
            DataColumn(label: Text('RSS'), numeric: true),
            DataColumn(label: Text('CELL')),
            DataColumn(label: Text('STATUS')),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                cells: [
                  DataCell(Text('#${row.drone.droneId}')),
                  DataCell(Text('${row.drone.battery}%')),
                  DataCell(Text(row.drone.altitude.toStringAsFixed(0))),
                  DataCell(Text(row.rssDbm?.toStringAsFixed(1) ?? '—')),
                  DataCell(Text(row.drone.cellId ?? '—')),
                  DataCell(StatusChip(
                    severity: droneSeverity(row.drone),
                    label: _statusLabel(row.drone.status),
                  )),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(String status) => switch (status) {
      'active' => '정상',
      'returning' => '복귀 중',
      'lost' => 'Offline',
      _ => status,
    };
