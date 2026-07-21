import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/connection_badge.dart';
import '../../core/widgets/queue_chip.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/severity.dart';
import '../../models/detection_event.dart';
import '../detection/detection_sheet.dart';
import '../detection/providers/detection_queue_provider.dart';
import 'providers/drones_provider.dart';
import 'providers/ws_providers.dart';
import 'widgets/drone_list_sheet.dart';
import 'widgets/heatmap_painter.dart';
import 'widgets/legend_popup.dart';
import 'widgets/marker_layer.dart';
import 'widgets/offline_banner.dart';

/// 관제 화면 — the app's home tab. Map occupies ~82% of the screen; the
/// drone list sheet always peeks at the bottom; the map itself is never
/// covered by a Fullscreen Dialog.
class ControlScreen extends ConsumerStatefulWidget {
  const ControlScreen({super.key});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen> {
  final _mapController = MapController();
  bool _centeredOnFirstDrone = false;
  bool _detectionSheetOpen = false;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  // 통화 중이든 그냥 최소화한 상태든, 시트가 열려 있는 동안엔 새 탐지가 끼어들지
  // 않는다 — 큐 칩 숫자만 늘어나고, 현재 시트가 끝나야 다음 걸 연다.
  Future<void> _openDetectionSheet(DetectionEvent event) async {
    setState(() => _detectionSheetOpen = true);
    final outcome = await showDetectionSheet(context, event);
    if (!mounted) return;
    setState(() => _detectionSheetOpen = false);
    if (outcome != DetectionOutcome.minimized) {
      final queue = ref.read(detectionQueueProvider);
      if (queue.isNotEmpty) _openDetectionSheet(queue.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-pan to the first drone once telemetry starts arriving.
    ref.listen(dronesProvider, (previous, next) {
      if (!_centeredOnFirstDrone && next.isNotEmpty) {
        _centeredOnFirstDrone = true;
        _mapController.move(next.values.first.position, 15);
      }
    });

    // 큐가 "비어있음 → 있음"으로 바뀔 때만 자동으로 연다. 이미 최소화된 채로
    // 대기 중인 상태에서 새 탐지가 추가되는 건(길이만 증가) 자동으로 다시 열지
    // 않는다 — 큐 칩 숫자만 올라간다.
    ref.listen<List<DetectionEvent>>(detectionQueueProvider, (previous, next) {
      final wasEmpty = previous == null || previous.isEmpty;
      if (wasEmpty && next.isNotEmpty && !_detectionSheetOpen) {
        _openDetectionSheet(next.first);
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(37.5012, 127.0262), // 강남↔신논현 중간
              initialZoom: 15,
              interactionOptions: InteractionOptions(flags: InteractiveFlag.all),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.drone.control_app',
              ),
              const HeatmapPainterLayer(),
              const DroneMarkerLayer(),
            ],
          ),
          const Positioned(top: 0, left: 0, right: 0, child: OfflineBanner()),
          Positioned(
            top: AppSpacing.md,
            left: AppSpacing.md,
            right: AppSpacing.md,
            child: Row(
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final status = ref.watch(wsConnectionProvider);
                    return ConnectionBadge(
                      status: status.value ?? ConnectionStatus.connecting,
                    );
                  },
                ),
                const SizedBox(width: AppSpacing.sm),
                Consumer(
                  builder: (context, ref, _) {
                    final count = ref.watch(dronesProvider.select((d) => d.length));
                    return StatusChip(severity: Severity.ok, label: '드론 $count대');
                  },
                ),
                const Spacer(),
                Consumer(
                  builder: (context, ref, _) {
                    final queueCount =
                        ref.watch(detectionQueueProvider.select((q) => q.length));
                    return QueueChip(
                      count: queueCount,
                      onTap: _detectionSheetOpen
                          ? null
                          : () {
                              final queue = ref.read(detectionQueueProvider);
                              if (queue.isNotEmpty) _openDetectionSheet(queue.first);
                            },
                    );
                  },
                ),
              ],
            ),
          ),
          Positioned(
            right: AppSpacing.md,
            bottom: MediaQuery.of(context).size.height * 0.15 + AppSpacing.md,
            child: FloatingActionButton.small(
              heroTag: 'legend-fab',
              onPressed: () => showLegendPopup(context),
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.textPrimary,
              child: const Icon(Icons.layers_outlined),
            ),
          ),
          const DroneListSheet(),
        ],
      ),
    );
  }
}
