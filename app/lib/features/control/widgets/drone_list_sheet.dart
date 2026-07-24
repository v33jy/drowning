import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/severity.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../models/drone_state.dart';
import '../providers/drones_provider.dart';
import '../providers/heatmap_provider.dart';
import '../providers/video_frame_provider.dart';
import 'marker_layer.dart';

/// Drone info bar — always visible at the bottom of 관제. There is no
/// separate "전체 보기" view anymore — it never showed anything the compact
/// chip row + inline detail couldn't, so it was cut rather than kept as
/// redundant chrome. Tapping a chip expands that drone's detail inline,
/// right below the chip row.
class DroneListBar extends ConsumerStatefulWidget {
  const DroneListBar({super.key});

  @override
  ConsumerState<DroneListBar> createState() => _DroneListBarState();
}

class _DroneListBarState extends ConsumerState<DroneListBar> {
  int? _selectedDroneId;

  @override
  Widget build(BuildContext context) {
    final drones = ref.watch(dronesProvider);
    final heatmap = ref.watch(heatmapProvider);
    final rows = [
      for (final d in drones.values.toList()
        ..sort((a, b) => _severityRank(a).compareTo(_severityRank(b))))
        _DroneRow(drone: d, rssDbm: heatmap[d.cellId]?.rssDbm),
    ];

    _DroneRow? selectedRow;
    for (final r in rows) {
      if (r.drone.droneId == _selectedDroneId) {
        selectedRow = r;
        break;
      }
    }
    if (selectedRow == null && _selectedDroneId != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => setState(() => _selectedDroneId = null));
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
          boxShadow: [
            BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, -2)),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Text('드론 ${rows.length}대', style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  height: 44,
                  child: rows.isEmpty
                      ? const _EmptyDrones()
                      : _CompactChipRow(
                          rows: rows,
                          selectedId: _selectedDroneId,
                          onTap: (id) => setState(
                            () => _selectedDroneId = _selectedDroneId == id ? null : id,
                          ),
                        ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: selectedRow == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: _InlineDroneDetail(
                            row: selectedRow,
                            onClose: () => setState(() => _selectedDroneId = null),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
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
    return const Align(
      alignment: Alignment.centerLeft,
      child: Text('연결된 드론 없음', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
    );
  }
}

/// Compact chip per drone — tapping one expands/collapses its inline detail.
class _CompactChipRow extends StatelessWidget {
  const _CompactChipRow({required this.rows, required this.selectedId, required this.onTap});
  final List<_DroneRow> rows;
  final int? selectedId;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
      itemBuilder: (context, i) {
        final row = rows[i];
        final d = row.drone;
        final severity = droneSeverity(d);
        final selected = d.droneId == selectedId;
        return InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () => onTap(d.droneId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary.withValues(alpha: 0.1) : null,
              border: Border.all(color: selected ? AppColors.primary : AppColors.border),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SeverityDot(severity: severity),
                const SizedBox(width: AppSpacing.xs),
                Text('#${d.droneId}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${d.battery}%',
                  style: AppTypography.numeric(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shown inline below the chip row when a chip is selected — no separate
/// popup stacked on top of the bar.
class _InlineDroneDetail extends ConsumerWidget {
  const _InlineDroneDetail({required this.row, required this.onClose});
  final _DroneRow row;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frameB64 = ref.watch(videoFrameProvider.select((m) => m[row.drone.droneId]));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No "드론 #N" title here — the highlighted chip right above already
        // shows which drone is selected; repeating it here was redundant.
        Align(
          alignment: Alignment.centerRight,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onClose,
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close, size: 18, color: AppColors.textSecondary),
            ),
          ),
        ),
        _DroneKeyValueTable(row: row),
        const SizedBox(height: AppSpacing.sm),
        _VideoThumbnail(frameB64: frameB64),
      ],
    );
  }
}

/// Rough live-glance preview — last received frame only, no buffering or
/// real player. Just enough to show "this is roughly what the drone sees".
/// Full-width, below the stat table — a side thumbnail read as an
/// afterthought; this is meant to be the second thing you look at.
class _VideoThumbnail extends StatelessWidget {
  const _VideoThumbnail({required this.frameB64});
  final String? frameB64;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        width: double.infinity,
        height: 160,
        color: AppColors.surfaceSunken,
        child: frameB64 == null
            ? const Center(
                child: Icon(Icons.videocam_off_outlined, size: 28, color: AppColors.textSecondary),
              )
            : Image.memory(base64Decode(frameB64!), fit: BoxFit.contain, gaplessPlayback: true),
      ),
    );
  }
}

/// Single-drone table — attribute-per-column, one label row + one value row.
/// This bottom bar is very wide, so a column-per-attribute strip fills it
/// naturally; a row-per-attribute list left it narrow with a huge empty
/// gutter beside it no matter how tight the column widths got.
class _DroneKeyValueTable extends StatelessWidget {
  const _DroneKeyValueTable({required this.row});
  final _DroneRow row;

  @override
  Widget build(BuildContext context) {
    final d = row.drone;
    return Table(
      border: TableBorder.all(color: AppColors.border, width: 1, borderRadius: BorderRadius.circular(AppRadius.sm)),
      // Equal flex columns — the table stretches to fill this wide bottom
      // bar edge-to-edge instead of hugging content and floating small to
      // one side; centering each cell's content keeps the extra width from
      // reading as a lopsided empty gutter.
      columnWidths: const {
        0: FlexColumnWidth(),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(),
        4: FlexColumnWidth(),
      },
      children: [
        TableRow(
          decoration: const BoxDecoration(color: AppColors.surfaceSunken),
          children: [
            _headCell('배터리'),
            _headCell('고도'),
            _headCell('RSS'),
            _headCell('셀'),
            _headCell('상태'),
          ],
        ),
        TableRow(
          children: [
            _cell(Text('${d.battery}%', style: _valueStyle)),
            _cell(Text('${d.altitude.toStringAsFixed(0)} m', style: _valueStyle)),
            _cell(Text(row.rssDbm != null ? '${row.rssDbm!.toStringAsFixed(1)} dBm' : '—', style: _valueStyle)),
            _cell(Text(d.cellId ?? '—', style: _valueStyle)),
            _cell(StatusChip(severity: droneSeverity(d), label: droneStatusLabel(d))),
          ],
        ),
      ],
    );
  }

  static const _valueStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary);

  Widget _headCell(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Text(label, textAlign: TextAlign.center, style: AppTypography.eyebrow(AppColors.textSecondary)),
    );
  }

  Widget _cell(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Center(child: child),
    );
  }
}
