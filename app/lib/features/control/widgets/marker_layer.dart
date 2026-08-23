import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/severity.dart';
import '../../../models/drone_state.dart';
import '../providers/drones_provider.dart';
import 'drone_icon.dart';

Severity droneSeverity(DroneState d) {
  if (d.status == 'lost') return Severity.offline;
  final battery = d.battery;
  if (battery == null) return Severity.warning;
  if (battery <= 20) return Severity.danger;
  if (battery <= 40) return Severity.warning;
  return Severity.ok;
}

/// Label shown alongside [droneSeverity] — derived from the *same* battery
/// thresholds, never from the raw telemetry `status` string directly. Those
/// two used to be computed independently (severity from battery, label from
/// `status`), which could show "정상" in red when battery was critical.
String droneStatusLabel(DroneState d) {
  if (d.status == 'lost') return 'Offline';
  if (d.battery == null) return '배터리 미확인';

  return switch (droneSeverity(d)) {
    Severity.offline => 'Offline',
    Severity.danger => '위험',
    Severity.warning => '주의',
    Severity.ok => '정상',
  };
}

double droneMarkerScale(double zoom) =>
    (1 + (zoom - 15) * 0.16).clamp(0.75, 1.8).toDouble();

/// Drone markers only — rebuilds when [dronesProvider] changes, independent
/// of the FlutterMap widget itself (map position/zoom survives untouched).
class DroneMarkerLayer extends ConsumerWidget {
  const DroneMarkerLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drones = ref.watch(dronesProvider);
    final markerScale = droneMarkerScale(MapCamera.of(context).zoom);
    return MarkerLayer(
      markers: [
        for (final d in drones.values)
          Marker(
            key: ValueKey(d.droneId),
            point: d.position,
            width: 48 * markerScale,
            height: 48 * markerScale,
            child: Transform.scale(
              scale: markerScale,
              child: _DroneMarkerIcon(drone: d),
            ),
          ),
      ],
    );
  }
}

class _DroneMarkerIcon extends StatelessWidget {
  const _DroneMarkerIcon({required this.drone});
  final DroneState drone;

  @override
  Widget build(BuildContext context) {
    final color = droneSeverity(drone).resolve(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DroneIcon(color: color, size: 28),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            '#${drone.droneId}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
