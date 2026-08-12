import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/severity.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/video_thumbnail.dart';
import '../../../models/drone_state.dart';
import '../providers/drones_provider.dart';
import '../providers/heatmap_provider.dart';
import '../providers/video_frame_provider.dart';
import 'drone_icon.dart';
import 'marker_layer.dart';

/// Single-aircraft control bar. The providers remain keyed by drone ID so a
/// future multi-drone UI can be added without changing telemetry contracts.
class DroneListBar extends ConsumerStatefulWidget {
  const DroneListBar({super.key});

  @override
  ConsumerState<DroneListBar> createState() => _DroneListBarState();
}

class _DroneListBarState extends ConsumerState<DroneListBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final drones = ref.watch(dronesProvider).values.toList()
      ..sort((a, b) => a.droneId.compareTo(b.droneId));
    final drone = drones.firstOrNull;
    final rssDbm = drone == null
        ? null
        : ref.watch(
            heatmapProvider.select((cells) => cells[drone.cellId]?.rssDbm),
          );

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 8,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: drone == null
                ? const _EmptyDrone()
                : _SingleDronePanel(
                    drone: drone,
                    rssDbm: rssDbm,
                    expanded: _expanded,
                    onToggle: () => setState(() => _expanded = !_expanded),
                  ),
          ),
        ),
      ),
    );
  }
}

class _EmptyDrone extends StatelessWidget {
  const _EmptyDrone();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Text(
      '운용 드론 연결 대기 중',
      style: TextStyle(color: AppColors.textSecondary),
    ),
  );
}

class _SingleDronePanel extends ConsumerWidget {
  const _SingleDronePanel({
    required this.drone,
    required this.rssDbm,
    required this.expanded,
    required this.onToggle,
  });

  final DroneState drone;
  final double? rssDbm;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final severity = droneSeverity(drone);
    final frameB64 = ref.watch(
      videoFrameProvider.select((frames) => frames[drone.droneId]),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                DroneIcon(color: severity.resolve(context), size: 30),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '운용 드론 #${drone.droneId}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '배터리 ${drone.battery}% · 고도 ${drone.altitude.toStringAsFixed(0)}m',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                StatusChip(severity: severity, label: droneStatusLabel(drone)),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_up,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Column(
                    children: [
                      _DroneMetrics(drone: drone, rssDbm: rssDbm),
                      const SizedBox(height: AppSpacing.sm),
                      VideoThumbnail(frameB64: frameB64),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _DroneMetrics extends StatelessWidget {
  const _DroneMetrics({required this.drone, required this.rssDbm});

  final DroneState drone;
  final double? rssDbm;

  @override
  Widget build(BuildContext context) => Table(
    border: TableBorder.all(
      color: AppColors.border,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    children: [
      TableRow(
        decoration: const BoxDecoration(color: AppColors.surfaceSunken),
        children: [
          '배터리',
          '고도',
          'RSS',
          '수색 구역',
        ].map((label) => _cell(label, header: true)).toList(),
      ),
      TableRow(
        children: [
          _cell('${drone.battery}%'),
          _cell('${drone.altitude.toStringAsFixed(0)} m'),
          _cell(rssDbm == null ? '—' : '${rssDbm!.toStringAsFixed(1)} dBm'),
          _cell(drone.cellId ?? '—'),
        ],
      ),
    ],
  );

  Widget _cell(String value, {bool header = false}) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.sm,
    ),
    child: Text(
      value,
      textAlign: TextAlign.center,
      style: header
          ? AppTypography.eyebrow(AppColors.textSecondary)
          : const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
  );
}
